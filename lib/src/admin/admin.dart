import "package:http/http.dart" as http;

import "../client.dart";
import "../data/crud.dart";
import "../internal/encode.dart";
import "../types.dart";

class Resource<T extends Json> {
  Resource(this.rb, this.path);
  final RustaBase rb;
  final String path;
  T convert(Json data) => data as T;
  Future<List<T>> list({
    RequestOptions options = const RequestOptions(),
  }) async =>
      (await rb.request<List<dynamic>>(
        path,
        options: options.copyWith(method: "GET"),
      ))
          .map((item) => convert(Map<String, dynamic>.from(item as Map)))
          .toList();
  Future<T> get(String id, {RequestOptions options = const RequestOptions()}) =>
      rb.request<T>(
        "$path/${seg(id)}",
        options: options.copyWith(method: "GET"),
      );
  Future<T> create(
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<T>(
        path,
        options: options.copyWith(method: "POST", body: data),
      );
  Future<T> update(
    String id,
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<T>(
        "$path/${seg(id)}",
        options: options.copyWith(method: "PATCH", body: data),
      );
  Future<bool> remove(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "$path/${seg(id)}",
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }

  Future<R> action<R>(
    String id,
    String name,
    String method, {
    Object? body,
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<R>(
        "$path/${seg(id)}/$name",
        options: options.copyWith(method: method, body: body),
      );
}

class Collections extends Crud<Json> {
  Collections(RustaBase rb) : super(rb, "/api/collections");
  Future<bool> import(
    List<Json> collections, {
    bool deleteMissing = false,
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "$path/import",
      options: options.copyWith(
        method: "PUT",
        body: {"collections": collections, "deleteMissing": deleteMissing},
      ),
    );
    return true;
  }

  Future<bool> truncate(
    String collection, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "$path/${seg(collection)}/truncate",
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }

  Future<Map<String, Json>> scaffolds({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Map<String, Json>>(
        "$path/meta/scaffolds",
        options: options.copyWith(method: "GET"),
      );
  Future<List<dynamic>> oauthProviders({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "$path/meta/oauth2-providers",
        options: options.copyWith(method: "GET"),
      );
  Future<Json> previewView(
    String query, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "$path/meta/dry-run-view",
        options: options.copyWith(method: "POST", body: {"query": query}),
      );
}

class Settings {
  const Settings(this.rb);
  final RustaBase rb;
  Future<Json> get({RequestOptions options = const RequestOptions()}) => rb
      .request<Json>("/api/settings", options: options.copyWith(method: "GET"));
  Future<Json> update(
    Json data, {
    List<http.MultipartFile> files = const [],
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/settings",
        options: options.copyWith(method: "PATCH", body: data, files: files),
      );
  Future<bool> testStorage({
    String filesystem = "storage",
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/settings/test/s3",
      options: options.copyWith(
        method: "POST",
        body: {"filesystem": filesystem},
      ),
    );
    return true;
  }

  Future<bool> testEmail(
    String collection,
    String to,
    String template, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/settings/test/email",
      options: options.copyWith(
        method: "POST",
        body: {"email": to, "template": template, "collection": collection},
      ),
    );
    return true;
  }

  Future<Json> appleClientSecret(
    Json input, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/settings/apple/generate-client-secret",
        options: options.copyWith(method: "POST", body: input),
      );
}

class Logs {
  const Logs(this.rb);
  final RustaBase rb;
  Future<Page<Json>> list({ListOptions options = const ListOptions()}) async {
    final data = await rb.request<Json>(
      "/api/logs",
      options: RequestOptions(
        method: "GET",
        query: readQuery(
          options,
          page: options.page,
          perPage: options.perPage,
          filter: options.filter,
          sort: options.sort,
          skipTotal: options.skipTotal,
        ),
        headers: options.headers,
      ),
    );
    return Page.fromJson(data, (item) => item);
  }

  Future<Json> get(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/logs/${seg(id)}",
        options: options.copyWith(method: "GET"),
      );
  Future<List<dynamic>> stats({
    String? filter,
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "/api/logs/stats",
        options: options.copyWith(
          method: "GET",
          query: {if (filter != null) "filter": filter, ...options.query},
        ),
      );
  Future<bool> clear({RequestOptions options = const RequestOptions()}) async {
    await rb.request<Object?>(
      "/api/logs",
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }
}

class Backups {
  const Backups(this.rb);
  final RustaBase rb;
  Future<List<dynamic>> list({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "/api/backups",
        options: options.copyWith(method: "GET"),
      );
  Future<bool> create({
    String name = "",
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/backups",
      options: options.copyWith(method: "POST", body: {"name": name}),
    );
    return true;
  }

  Future<bool> upload(
    List<http.MultipartFile> files, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/backups/upload",
      options: options.copyWith(method: "POST", files: files),
    );
    return true;
  }

  Future<bool> remove(
    String key, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/backups/${seg(key)}",
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }

  Future<bool> restore(
    String key, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/backups/${seg(key)}/restore",
      options: options.copyWith(method: "POST"),
    );
    return true;
  }

  String downloadUrl(String key, String token) =>
      rb.url("/api/backups/${seg(key)}?token=${seg(token)}");
}

class Crons {
  const Crons(this.rb);
  final RustaBase rb;
  Future<List<dynamic>> list({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "/api/crons",
        options: options.copyWith(method: "GET"),
      );
  Future<bool> run(
    String jobId, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      "/api/crons/${seg(jobId)}",
      options: options.copyWith(method: "POST"),
    );
    return true;
  }
}

class ApiKeys extends Resource<Json> {
  ApiKeys(RustaBase rb) : super(rb, "/api/api-keys");
  Future<Json> rotate(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) =>
      action<Json>(id, "rotate", "POST", options: options);
}

class Webhooks extends Resource<Json> {
  Webhooks(RustaBase rb) : super(rb, "/api/webhooks");
  Future<Json> stats({RequestOptions options = const RequestOptions()}) =>
      rb.request<Json>("$path/stats", options: options.copyWith(method: "GET"));
  Future<Json> test(
    String id, {
    Json payload = const {},
    RequestOptions options = const RequestOptions(),
  }) =>
      action<Json>(id, "test", "POST", body: payload, options: options);
}

class Functions extends Resource<Json> {
  Functions(RustaBase rb) : super(rb, "/api/functions");
  Future<Json> stats({RequestOptions options = const RequestOptions()}) =>
      rb.request<Json>("$path/stats", options: options.copyWith(method: "GET"));
  Future<Json> duplicate(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) =>
      action<Json>(id, "duplicate", "POST", options: options);
  Future<Json> test(
    String id, {
    Json payload = const {},
    RequestOptions options = const RequestOptions(),
  }) =>
      action<Json>(id, "test", "POST", body: payload, options: options);
  Future<List<dynamic>> logs(
    String id, {
    String? status,
    int? limit,
    RequestOptions options = const RequestOptions(),
  }) =>
      action<List<dynamic>>(
        id,
        "logs",
        "GET",
        options: options.copyWith(
          query: {
            if (status != null) "status": status,
            if (limit != null) "limit": limit,
            ...options.query,
          },
        ),
      );
  Future<bool> clearLogs(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await action<Object?>(id, "logs", "DELETE", options: options);
    return true;
  }
}

class Rls {
  const Rls(this.rb);
  final RustaBase rb;
  String path(String table, [String rest = ""]) =>
      "/api/rls/tables/${seg(table)}$rest";
  Future<List<dynamic>> templates({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "/api/rls/templates",
        options: options.copyWith(method: "GET"),
      );
  Future<List<dynamic>> tables({
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        "/api/rls/tables",
        options: options.copyWith(method: "GET"),
      );
  Future<List<dynamic>> policies(
    String table, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<List<dynamic>>(
        path(table, "/policies"),
        options: options.copyWith(method: "GET"),
      );
  Future<Json> createPolicy(
    String table,
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        path(table, "/policies"),
        options: options.copyWith(method: "POST", body: data),
      );
  Future<Json> updatePolicy(
    String table,
    String name,
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        path(table, "/policies/${seg(name)}"),
        options: options.copyWith(method: "PATCH", body: data),
      );
  Future<bool> removePolicy(
    String table,
    String name, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      path(table, "/policies/${seg(name)}"),
      options: options.copyWith(method: "DELETE"),
    );
    return true;
  }

  Future<bool> setEnabled(
    String table, {
    required bool enabled,
    bool? force,
    RequestOptions options = const RequestOptions(),
  }) async {
    await rb.request<Object?>(
      path(table, "/rls"),
      options: options.copyWith(
        method: "POST",
        body: {"enabled": enabled, if (force != null) "force": force},
      ),
    );
    return true;
  }

  Future<Json> preview(
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/rls/preview",
        options: options.copyWith(method: "POST", body: data),
      );
  Future<Json> test(
    Json data, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/rls/test",
        options: options.copyWith(method: "POST", body: data),
      );
}

class Admin {
  Admin(this.rb)
      : collections = Collections(rb),
        settings = Settings(rb),
        logs = Logs(rb),
        backups = Backups(rb),
        crons = Crons(rb),
        apiKeys = ApiKeys(rb),
        webhooks = Webhooks(rb),
        functions = Functions(rb),
        rls = Rls(rb);
  final RustaBase rb;
  final Collections collections;
  final Settings settings;
  final Logs logs;
  final Backups backups;
  final Crons crons;
  final ApiKeys apiKeys;
  final Webhooks webhooks;
  final Functions functions;
  final Rls rls;
  Future<Json> sql(
    String query, {
    RequestOptions options = const RequestOptions(),
  }) =>
      rb.request<Json>(
        "/api/sql",
        options: options.copyWith(method: "POST", body: {"query": query}),
      );
}
