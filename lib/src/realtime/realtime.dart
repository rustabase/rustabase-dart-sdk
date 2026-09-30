import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../client.dart";
import "../errors.dart";
import "../protocol.dart";
import "../types.dart";

typedef RealtimeCallback = void Function(Json event);

class Realtime {
  Realtime(this.rb);
  final RustaBase rb;
  String clientId = "";
  num maxRetries = double.infinity;
  void Function(List<String> activeTopics)? onDisconnect;
  final Map<String, List<RealtimeCallback>> _topics = {};
  http.Client? _client;
  StreamSubscription<String>? _stream;
  Timer? _retryTimer;
  bool _closed = false;
  int _retries = 0;

  bool get isConnected => clientId.isNotEmpty && _stream != null;

  Future<Unsubscribe> subscribe(
    String topic,
    RealtimeCallback callback, {
    RequestOptions options = const RequestOptions(),
  }) async {
    if (topic.isEmpty) throw ArgumentError("A topic is required.");
    var key = topic;
    if (options.query.isNotEmpty || options.headers.isNotEmpty) {
      key +=
          "${key.contains('?') ? '&' : '?'}options=${Uri.encodeQueryComponent(jsonEncode({
            "query": options.query,
            "headers": options.headers
          }))}";
    }
    (_topics[key] ??= []).add(callback);
    try {
      if (_stream == null)
        await _connect();
      else
        await _sync();
    } catch (error) {
      _topics[key]?.remove(callback);
      if (_topics[key]?.isEmpty ?? false) _topics.remove(key);
      rethrow;
    }
    return () async {
      _topics[key]?.remove(callback);
      if (_topics[key]?.isEmpty ?? false) _topics.remove(key);
      await _sync();
    };
  }

  Future<void> unsubscribe([String? topic]) async {
    if (topic == null)
      _topics.clear();
    else
      _topics.removeWhere((key, _) => key.split("?").first == topic);
    await _sync();
  }

  Future<void> unsubscribeByPrefix(String prefix) async {
    _topics.removeWhere((key, _) {
      final base = key.split("?").first;
      return base == prefix || base.startsWith("$prefix/");
    });
    await _sync();
  }

  void disconnect() {
    final active = _topics.keys.toList();
    _topics.clear();
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stream?.cancel();
    _client?.close();
    _stream = null;
    _client = null;
    clientId = "";
    if (active.isNotEmpty) onDisconnect?.call(active);
  }

  Future<void> _connect() async {
    _closed = false;
    final ready = Completer<void>();
    final client = rb.httpClientFactory();
    _client = client;
    try {
      final response = await client.send(
        http.Request("GET", Uri.parse(rb.url("/api/realtime"))),
      );
      if (response.statusCode >= 400)
        throw RustaBaseError(
          status: response.statusCode,
          url: rb.url("/api/realtime"),
        );
      var event = "";
      var id = "";
      final data = StringBuffer();
      _stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) async {
          if (line.isEmpty) {
            Object? decoded;
            try {
              decoded = data.isEmpty ? null : jsonDecode(data.toString());
            } on FormatException {
              // Skip malformed event payloads instead of killing the stream.
              event = "";
              id = "";
              data.clear();
              return;
            }
            final payload = decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : <String, dynamic>{};
            if (event == rbConnect) {
              clientId = id;
              _retries = 0;
              try {
                await _sync();
              } catch (error) {
                // A failed initial sync must surface as a connect error and
                // enter the retry loop, not escape as an unhandled async
                // error inside the stream listener.
                await _teardown();
                if (!ready.isCompleted) {
                  ready.completeError(RustaBaseError.from(error));
                }
                _retry();
                return;
              }
              if (!ready.isCompleted) ready.complete();
            }
            for (final callback in List<RealtimeCallback>.from(
              _topics[event] ?? const [],
            )) {
              try {
                callback(payload);
              } catch (_) {
                // A throwing subscriber must not kill the event stream.
              }
            }
            event = "";
            id = "";
            data.clear();
            return;
          }
          if (line.startsWith("event:")) event = line.substring(6).trim();
          if (line.startsWith("id:")) id = line.substring(3).trim();
          if (line.startsWith("data:")) {
            // Per the SSE spec, strip at most one leading space; trimming
            // would corrupt whitespace inside JSON string values.
            var value = line.substring(5);
            if (value.startsWith(" ")) value = value.substring(1);
            if (data.isNotEmpty) data.write("\n");
            data.write(value);
          }
        },
        onError: (Object error) {
          if (!ready.isCompleted)
            ready.completeError(RustaBaseError.from(error));
          _retry();
        },
        onDone: () {
          if (!ready.isCompleted)
            ready.completeError(
              RustaBaseError(message: "The live connection ended."),
            );
          _retry();
        },
      );
      await ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            throw RustaBaseError(message: "The live connection timed out."),
      );
    } catch (error) {
      await _teardown();
      throw RustaBaseError.from(error);
    }
  }

  /// Cancels the SSE subscription and closes the underlying client so a
  /// failed or replaced connection never keeps reading in the background.
  Future<void> _teardown() async {
    await _stream?.cancel();
    _stream = null;
    _client?.close();
    _client = null;
  }

  Future<void> _sync() async {
    if (_topics.isEmpty) {
      await _teardown();
      clientId = "";
      return;
    }
    if (clientId.isEmpty) return;
    await rb.request<Object?>(
      "/api/realtime",
      options: RequestOptions(
        method: "POST",
        body: {"clientId": clientId, "subscriptions": _topics.keys.toList()},
        requestKey: "realtime:$clientId",
      ),
    );
  }

  void _retry() {
    if (_closed || _topics.isEmpty || _retries >= maxRetries) {
      final active = _topics.keys.toList();
      clientId = "";
      if (active.isNotEmpty) onDisconnect?.call(active);
      return;
    }
    final delay = _retryDelay(_retries);
    _retries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      if (!_closed) {
        try {
          await _connect();
        } catch (_) {
          _retry();
        }
      }
    });
  }

  Duration _retryDelay(int attempt) {
    final exponent = attempt.clamp(0, 5);
    final base = 250 * (1 << exponent);
    final jitter = ((attempt + 1) * 97) % 211;
    return Duration(milliseconds: (base + jitter).clamp(250, 6000));
  }
}
