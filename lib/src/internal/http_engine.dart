import "dart:convert";

import "package:http/http.dart" as http;

class HttpExchange {
  const HttpExchange({
    required this.status,
    required this.reason,
    required this.response,
    required this.data,
  });

  final int status;
  final String reason;
  final http.BaseResponse response;
  final Object? data;
}

class HttpEngine {
  HttpEngine({
    required http.Client Function() createClient,
    required bool reuseClient,
  })  : _createClient = createClient,
        _shared = reuseClient ? createClient() : null;

  final http.Client Function() _createClient;
  http.Client? _shared;

  Future<HttpExchange> execute({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    Object? body,
    List<http.MultipartFile> files = const [],
  }) async {
    final client = _shared ?? _createClient();
    try {
      final request = _buildRequest(
        uri: uri,
        method: method,
        headers: headers,
        body: body,
        files: files,
      );
      final response = await client.send(request);
      final bytes = await response.stream.toBytes();
      return HttpExchange(
        status: response.statusCode,
        reason: response.reasonPhrase ?? "",
        response: response,
        data: _decode(bytes),
      );
    } finally {
      if (_shared == null) {
        client.close();
      }
    }
  }

  http.BaseRequest _buildRequest({
    required Uri uri,
    required String method,
    required Map<String, String> headers,
    required Object? body,
    required List<http.MultipartFile> files,
  }) {
    if (files.isNotEmpty) {
      final request = http.MultipartRequest(method, uri)
        ..headers.addAll(headers);
      if (body is Map) {
        for (final entry in body.entries) {
          request.fields[entry.key.toString()] = _fieldValue(entry.value);
        }
      }
      request.files.addAll(files);
      return request;
    }

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.headers.putIfAbsent("Content-Type", () => "application/json");
      request.body = body is String ? body : jsonEncode(body);
    }
    return request;
  }

  String _fieldValue(Object? value) =>
      value is String ? value : jsonEncode(value);

  Object? _decode(List<int> bytes) {
    if (bytes.isEmpty) {
      return <String, dynamic>{};
    }
    final text = utf8.decode(bytes);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  void close() {
    _shared?.close();
    _shared = null;
  }
}

class RequestLedger {
  final Map<String, int> _active = {};
  int _nextTicket = 1;

  int begin(String key) {
    final ticket = _nextTicket++;
    _active[key] = ticket;
    return ticket;
  }

  bool owns(String key, int ticket) => _active[key] == ticket;

  void finish(String key, int ticket) {
    if (owns(key, ticket)) {
      _active.remove(key);
    }
  }

  void cancel(String key) => _active.remove(key);

  void cancelAll() => _active.clear();
}
