import "package:http/http.dart" as http;

typedef Json = Map<String, dynamic>;
typedef Row = Map<String, dynamic>;
typedef Unsubscribe = Future<void> Function();

class RequestOptions {
  const RequestOptions({
    this.query = const {},
    this.headers = const {},
    this.body,
    this.files = const [],
    this.method,
    this.requestKey,
    this.autoCancel = true,
  });

  final Json query;
  final Map<String, String> headers;
  final Object? body;
  final List<http.MultipartFile> files;
  final String? method;
  final String? requestKey;
  final bool autoCancel;

  RequestOptions copyWith({
    Json? query,
    Map<String, String>? headers,
    Object? body,
    List<http.MultipartFile>? files,
    String? method,
    String? requestKey,
    bool? autoCancel,
  }) =>
      RequestOptions(
        query: query ?? this.query,
        headers: headers ?? this.headers,
        body: body ?? this.body,
        files: files ?? this.files,
        method: method ?? this.method,
        requestKey: requestKey ?? this.requestKey,
        autoCancel: autoCancel ?? this.autoCancel,
      );
}

class ReadOptions extends RequestOptions {
  const ReadOptions({
    super.query,
    super.headers,
    super.body,
    super.files,
    super.method,
    super.requestKey,
    super.autoCancel,
    this.expand,
    this.fields,
  });
  final String? expand;
  final String? fields;
}

class ListOptions extends ReadOptions {
  const ListOptions({
    super.query,
    super.headers,
    super.requestKey,
    super.autoCancel,
    super.expand,
    super.fields,
    this.page = 1,
    this.perPage = 30,
    this.filter,
    this.sort,
    this.skipTotal,
  });
  final int page;
  final int perPage;
  final String? filter;
  final String? sort;
  final bool? skipTotal;
}

class AllOptions extends ReadOptions {
  const AllOptions({
    super.query,
    super.headers,
    super.requestKey,
    super.autoCancel,
    super.expand,
    super.fields,
    this.filter,
    this.sort,
    this.skipTotal,
    this.chunk = 1000,
  });
  final String? filter;
  final String? sort;
  final bool? skipTotal;
  final int chunk;
}

class Page<T> {
  const Page({
    required this.page,
    required this.perPage,
    required this.totalItems,
    required this.totalPages,
    required this.items,
  });
  final int page;
  final int perPage;
  final int totalItems;
  final int totalPages;
  final List<T> items;

  factory Page.fromJson(Json json, T Function(Json) convert) => Page(
        page: (json["page"] as num?)?.toInt() ?? 0,
        perPage: (json["perPage"] as num?)?.toInt() ?? 0,
        totalItems: (json["totalItems"] as num?)?.toInt() ?? 0,
        totalPages: (json["totalPages"] as num?)?.toInt() ?? 0,
        items: (json["items"] as List<dynamic>? ?? const [])
            .map((item) => convert(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class AuthResult<T extends Row> {
  const AuthResult({
    required this.token,
    required this.record,
    this.meta = const {},
  });
  final String token;
  final T record;
  final Json meta;
}

class RealtimeEvent<T extends Row> {
  const RealtimeEvent({required this.action, required this.record});
  final String action;
  final T record;
  factory RealtimeEvent.fromJson(Json json) => RealtimeEvent(
        action: json["action"] as String? ?? "",
        record:
            Map<String, dynamic>.from(json["record"] as Map? ?? const {}) as T,
      );
}

class BatchResult {
  const BatchResult({required this.status, required this.body});
  final int status;
  final Object? body;
  factory BatchResult.fromJson(Json json) => BatchResult(
        status: (json["status"] as num?)?.toInt() ?? 0,
        body: json["body"],
      );
}
