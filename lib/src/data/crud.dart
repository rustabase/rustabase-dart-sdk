import "package:http/http.dart" as http;

import "../client.dart";
import "../errors.dart";
import "../internal/encode.dart";
import "../types.dart";

Json readQuery(
  ReadOptions options, {
  int? page,
  int? perPage,
  String? filter,
  String? sort,
  bool? skipTotal,
}) =>
    {
      if (page != null) "page": page,
      if (perPage != null) "perPage": perPage,
      if (filter != null) "filter": filter,
      if (sort != null) "sort": sort,
      if (skipTotal != null) "skipTotal": skipTotal,
      if (options.expand != null) "expand": options.expand,
      if (options.fields != null) "fields": options.fields,
      ...options.query,
    };

class Crud<T extends Row> {
  Crud(this.rb, this.path);
  final RustaBase rb;
  final String path;
  T convert(Json value) => value as T;

  Future<Page<T>> list({ListOptions options = const ListOptions()}) async {
    final data = await rb.request<Json>(
      path,
      options: RequestOptions(
        method: "GET",
        headers: options.headers,
        requestKey: options.requestKey,
        autoCancel: options.autoCancel,
        query: readQuery(
          options,
          page: options.page,
          perPage: options.perPage,
          filter: options.filter,
          sort: options.sort,
          skipTotal: options.skipTotal,
        ),
      ),
    );
    return Page.fromJson(data, convert);
  }

  Future<List<T>> all({AllOptions options = const AllOptions()}) async {
    if (options.chunk < 1)
      throw ArgumentError.value(options.chunk, "chunk", "must be at least 1");
    final out = <T>[];
    for (var page = 1;; page++) {
      final result = await list(
        options: ListOptions(
          page: page,
          perPage: options.chunk,
          filter: options.filter,
          sort: options.sort,
          skipTotal: true,
          expand: options.expand,
          fields: options.fields,
          query: options.query,
          headers: options.headers,
          autoCancel: false,
        ),
      );
      out.addAll(result.items);
      if (result.items.length < result.perPage) return out;
    }
  }

  Future<T> first(
    String filter, {
    ReadOptions options = const ReadOptions(),
  }) async {
    final result = await list(
      options: ListOptions(
        page: 1,
        perPage: 1,
        filter: filter,
        skipTotal: true,
        expand: options.expand,
        fields: options.fields,
        query: options.query,
        headers: options.headers,
        requestKey: options.requestKey ?? "first $path $filter",
      ),
    );
    if (result.items.isEmpty)
      throw RustaBaseError(
        status: 404,
        url: rb.url(path),
        data: {
          "code": 404,
          "message": "No row matches the filter.",
          "data": <String, dynamic>{},
        },
      );
    return result.items.first;
  }

  Future<T> get(String id, {ReadOptions options = const ReadOptions()}) {
    _requireId(id);
    return rb.request<T>(
      "$path/${seg(id)}",
      options: RequestOptions(
        method: "GET",
        query: readQuery(options),
        headers: options.headers,
        requestKey: options.requestKey,
        autoCancel: options.autoCancel,
      ),
    );
  }

  Future<T> create(
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) =>
      rb.request<T>(
        path,
        options: RequestOptions(
          method: "POST",
          body: data,
          files: files,
          query: readQuery(options),
          headers: options.headers,
          requestKey: options.requestKey,
          autoCancel: options.autoCancel,
        ),
      );
  Future<T> update(
    String id,
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) {
    _requireId(id);
    return rb.request<T>(
      "$path/${seg(id)}",
      options: RequestOptions(
        method: "PATCH",
        body: data,
        files: files,
        query: readQuery(options),
        headers: options.headers,
        requestKey: options.requestKey,
        autoCancel: options.autoCancel,
      ),
    );
  }

  Future<bool> remove(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) async {
    _requireId(id);
    await rb.request<Object?>(
      "$path/${seg(id)}",
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }

  void _requireId(String id) {
    if (id.isEmpty)
      throw RustaBaseError(
        status: 404,
        url: rb.url("$path/"),
        data: {
          "code": 404,
          "message": "An id is required.",
          "data": <String, dynamic>{},
        },
      );
  }
}
