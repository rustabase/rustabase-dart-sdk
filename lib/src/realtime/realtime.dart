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
            final payload = data.isEmpty
                ? <String, dynamic>{}
                : (jsonDecode(data.toString()) as Map<String, dynamic>);
            if (event == rbConnect) {
              clientId = id;
              _retries = 0;
              await _sync();
              if (!ready.isCompleted) ready.complete();
            }
            for (final callback in List<RealtimeCallback>.from(
              _topics[event] ?? const [],
            )) callback(payload);
            event = "";
            id = "";
            data.clear();
            return;
          }
          if (line.startsWith("event:")) event = line.substring(6).trim();
          if (line.startsWith("id:")) id = line.substring(3).trim();
          if (line.startsWith("data:")) {
            if (data.isNotEmpty) data.write("\n");
            data.write(line.substring(5).trim());
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
      _stream = null;
      _client?.close();
      _client = null;
      throw RustaBaseError.from(error);
    }
  }

  Future<void> _sync() async {
    if (_topics.isEmpty) {
      _stream?.cancel();
      _client?.close();
      _stream = null;
      _client = null;
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
    Timer(delay, () async {
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
