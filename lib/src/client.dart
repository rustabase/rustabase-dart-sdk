import "dart:async";
import "package:http/http.dart" as http;

import "admin/admin.dart";
import "data/batch.dart";
import "data/files.dart";
import "data/table.dart";
import "errors.dart";
import "internal/encode.dart";
import "internal/http_engine.dart";
import "internal/token.dart";
import "realtime/realtime.dart";
import "session/session.dart";
import "types.dart";

typedef RequestHook = FutureOr<RequestDetails?> Function(
    RequestDetails request);
typedef ResponseHook = FutureOr<Object?> Function(
    http.BaseResponse response, Object? data);

class RequestDetails {
  const RequestDetails({
    required this.url,
    required this.method,
    required this.headers,
    this.body,
    this.files = const [],
  });
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final Object? body;
  final List<http.MultipartFile> files;
  RequestDetails copyWith({
    Uri? url,
    String? method,
    Map<String, String>? headers,
    Object? body,
    List<http.MultipartFile>? files,
  }) =>
      RequestDetails(
        url: url ?? this.url,
        method: method ?? this.method,
        headers: headers ?? this.headers,
        body: body ?? this.body,
        files: files ?? this.files,
      );
}

class RustaBase {
  RustaBase(
    this.baseUrl, {
    Session? session,
    this.lang = "en-US",
    this.autoCancel = true,
    http.Client Function()? httpClientFactory,
    this.reuseHttpClient = false,
  })  : session = session ?? MemorySession(),
        httpClientFactory = httpClientFactory ?? http.Client.new {
    _http = HttpEngine(
      createClient: this.httpClientFactory,
      reuseClient: reuseHttpClient,
    );
    realtime = Realtime(this);
    files = Files(this);
    admin = Admin(this);
  }

  final String baseUrl;
  final Session session;
  String lang;
  bool autoCancel;
  final bool reuseHttpClient;
  final http.Client Function() httpClientFactory;
  RequestHook? onRequest;
  ResponseHook? onResponse;
  late final Realtime realtime;
  late final Files files;
  late final Admin admin;
  final Map<String, Table<Row>> _tables = {};
  final RequestLedger _requests = RequestLedger();
  late final HttpEngine _http;
  int? _keepAliveLeeway;
  Future<Object?> Function()? _keepAliveRun;
  StreamSubscription<SessionEvent>? _keepAliveSubscription;

  Table<T> from<T extends Row>(String collection) =>
      (_tables.putIfAbsent(collection, () => Table<Row>(this, collection))
          as Table<T>);
  AuthTable<T> auth<T extends Row>([String collection = "users"]) =>
      (_tables.putIfAbsent(
        "auth:$collection",
        () => AuthTable<Row>(this, collection),
      ) as AuthTable<T>);
  Batch batch() => Batch(this);
  String filter(String expression, [Json? params]) =>
      bindFilter(expression, params);
  String url([String path = ""]) => joinUrl(baseUrl, path);

  void signOut() {
    cancelAll();
    session.clear();
  }

  Future<Json> health({RequestOptions options = const RequestOptions()}) =>
      request<Json>("/api/health", options: options);

  void cancel(String requestKey) {
    _requests.cancel(requestKey);
  }

  void cancelAll() => _requests.cancelAll();

  Future<T> request<T>(
    String path, {
    RequestOptions options = const RequestOptions(),
  }) async {
    if (_keepAliveRun != null &&
        session.token.isNotEmpty &&
        tokenExpired(session.token, _keepAliveLeeway ?? 0)) {
      try {
        final refresh = _keepAliveRun;
        if (refresh != null) await refresh();
      } catch (_) {}
    }
    final method = (options.method ?? "GET").toUpperCase();
    final headers = Map<String, String>.from(options.headers);
    headers.putIfAbsent("Accept-Language", () => lang);
    if (session.token.isNotEmpty)
      headers.putIfAbsent("Authorization", () => session.token);
    var details = RequestDetails(
      url: Uri.parse(withQuery(url(path), options.query)),
      method: method,
      headers: headers,
      body: options.body,
      files: options.files,
    );
    final changed = await onRequest?.call(details);
    if (changed != null) details = changed;

    final key = autoCancel && options.autoCancel
        ? (options.requestKey ?? "$method ${withQuery(path, options.query)}")
        : null;
    final requestId = key == null ? null : _requests.begin(key);
    try {
      final exchange = await _http.execute(
        uri: details.url,
        method: details.method,
        headers: details.headers,
        body: details.body,
        files: details.files,
      );
      var data = await onResponse?.call(exchange.response, exchange.data) ??
          exchange.data;
      if (key != null && requestId != null && !_requests.owns(key, requestId))
        throw RustaBaseError(url: details.url.toString(), cancelled: true);
      if (exchange.status >= 400) {
        final payload = data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{
                "code": exchange.status,
                "message": exchange.reason.isEmpty
                    ? "Request failed."
                    : exchange.reason,
                "data": <String, dynamic>{},
              };
        throw RustaBaseError(
          url: details.url.toString(),
          status: exchange.status,
          data: payload,
        );
      }
      return data as T;
    } catch (error) {
      throw RustaBaseError.from(error, url: details.url.toString());
    } finally {
      if (key != null && requestId != null) _requests.finish(key, requestId);
    }
  }

  void setKeepAlive(int? leeway, Future<Object?> Function() run) {
    _keepAliveSubscription?.cancel();
    _keepAliveLeeway = leeway;
    _keepAliveRun = leeway == null || leeway <= 0 ? null : run;
    if (_keepAliveRun == null) return;
    final owner = session.record;
    _keepAliveSubscription = session.onChange.listen((event) {
      if (event.token.isEmpty ||
          event.record?["id"] != owner?["id"] ||
          event.record?["collectionId"] != owner?["collectionId"])
        setKeepAlive(null, run);
    });
  }

  void close() {
    realtime.disconnect();
    _keepAliveSubscription?.cancel();
    _http.close();
  }
}

RustaBase createClient(
  String baseUrl, {
  Session? session,
  String lang = "en-US",
  bool autoCancel = true,
  http.Client Function()? httpClientFactory,
  bool reuseHttpClient = false,
}) =>
    RustaBase(
      baseUrl,
      session: session,
      lang: lang,
      autoCancel: autoCancel,
      httpClientFactory: httpClientFactory,
      reuseHttpClient: reuseHttpClient,
    );
