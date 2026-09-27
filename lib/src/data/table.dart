import "dart:async";

import "package:http/http.dart" as http;

import "../client.dart";
import "../errors.dart";
import "../internal/encode.dart";
import "../internal/token.dart";
import "../realtime/realtime.dart";
import "../session/session.dart";
import "../types.dart";
import "crud.dart";

class Table<T extends Row> extends Crud<T> {
  Table(RustaBase rb, this.collection)
      : super(rb, "/api/collections/${seg(collection)}/records");
  final String collection;
  String get base => "/api/collections/${seg(collection)}";

  @override
  Future<T> update(
    String id,
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) async {
    final row = await super.update(id, data, files: files, options: options);
    final current = rb.session.record;
    if (current?["id"] == row["id"] && _matches(current)) {
      final expand = {
        ...(current?["expand"] as Map? ?? const {}),
        ...(row["expand"] as Map? ?? const {}),
      };
      rb.session.set(rb.session.token, {...?current, ...row, "expand": expand});
    }
    return row;
  }

  @override
  Future<bool> remove(
    String id, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await super.remove(id, options: options);
    if (rb.session.record?["id"] == id && _matches(rb.session.record))
      rb.session.clear();
    return true;
  }

  Future<Unsubscribe> subscribe(
    String target,
    void Function(RealtimeEvent<T>) callback, {
    ReadOptions options = const ReadOptions(),
    String? filter,
  }) {
    if (target.isEmpty)
      throw ArgumentError("subscribe() needs a target: \"*\" or a row id.");
    return rb.realtime.subscribe(
      "$collection/$target",
      (data) => callback(RealtimeEvent<T>.fromJson(data)),
      options: RequestOptions(
        query: {...readQuery(options), if (filter != null) "filter": filter},
        headers: options.headers,
      ),
    );
  }

  Future<void> unsubscribe([String? target]) => target == null
      ? rb.realtime.unsubscribeByPrefix(collection)
      : rb.realtime.unsubscribe("$collection/$target");
  bool _matches(Row? record) =>
      record?["collectionId"] == collection ||
      record?["collectionName"] == collection;
}

class AuthTable<T extends Row> extends Table<T> {
  AuthTable(super.rb, super.collection);

  Future<Json> methods({RequestOptions options = const RequestOptions()}) =>
      rb.request<Json>(
        "$base/auth-methods",
        options: options.copyWith(method: "GET"),
      );

  Future<AuthResult<T>> signInWithPassword(
    String identity,
    String password, {
    ReadOptions options = const ReadOptions(),
    int? keepAlive,
  }) async {
    Future<AuthResult<T>> send() async {
      final data = await rb.request<Json>(
        "$base/auth-with-password",
        options: RequestOptions(
          method: "POST",
          body: {"identity": identity, "password": password},
          query: readQuery(options),
          headers: options.headers,
          requestKey: options.requestKey,
          autoCancel: options.autoCancel,
        ),
      );
      return _save(data);
    }

    final result = await send();
    if (keepAlive != null && keepAlive > 0)
      rb.setKeepAlive(
        keepAlive,
        () => refresh(options: const ReadOptions(autoCancel: false)),
      );
    return result;
  }

  Future<Map<String, String>> requestOtp(
    String email, {
    RequestOptions options = const RequestOptions(),
  }) async {
    final data = await rb.request<Json>(
      "$base/request-otp",
      options: options.copyWith(method: "POST", body: {"email": email}),
    );
    return {"otpId": data["otpId"] as String? ?? ""};
  }

  Future<AuthResult<T>> signInWithOtp(
    String otpId,
    String code, {
    ReadOptions options = const ReadOptions(),
  }) async =>
      _save(
        await rb.request<Json>(
          "$base/auth-with-otp",
          options: RequestOptions(
            method: "POST",
            body: {"otpId": otpId, "password": code},
            query: readQuery(options),
            headers: options.headers,
            requestKey: options.requestKey,
            autoCancel: options.autoCancel,
          ),
        ),
      );

  Future<AuthResult<T>> signInWithOAuth({
    required String provider,
    required FutureOr<void> Function(Uri url) openUrl,
    List<String> scopes = const [],
    Json createData = const {},
    ReadOptions options = const ReadOptions(),
  }) async {
    final available = await methods();
    final oauth = available["oauth2"] as Map? ?? const {};
    final providers = oauth["providers"] as List? ?? const [];
    Map<String, dynamic>? match;
    for (final item in providers.cast<Map<String, dynamic>>()) {
      if (item["name"] == provider) {
        match = item;
        break;
      }
    }
    if (match == null) {
      throw RustaBaseError(message: "Unknown sign-in provider \"$provider\".");
    }
    final selectedProvider = match;
    final live = Realtime(rb);
    final completer = Completer<AuthResult<T>>();
    try {
      await live.subscribe("@oauth2", (event) async {
        try {
          if (event["state"] != live.clientId)
            throw RustaBaseError(
              message: "The sign-in response didn't match this request.",
            );
          if (event["error"] != null || event["code"] == null)
            throw RustaBaseError(message: "The provider returned an error.");
          completer.complete(
            await signInWithOAuthCode(
              provider: provider,
              code: event["code"].toString(),
              codeVerifier: selectedProvider["codeVerifier"]?.toString() ?? "",
              redirectUrl: rb.url("/api/oauth2-redirect"),
              createData: createData,
              options: options,
            ),
          );
        } catch (error) {
          completer.completeError(RustaBaseError.from(error));
        } finally {
          live.disconnect();
        }
      });
      final authUrl = Uri.parse(
        "${selectedProvider["authURL"]}${Uri.encodeComponent(rb.url('/api/oauth2-redirect'))}",
      );
      await openUrl(
        authUrl.replace(
          queryParameters: {
            ...authUrl.queryParameters,
            "state": live.clientId,
            if (scopes.isNotEmpty) "scope": scopes.join(" "),
          },
        ),
      );
    } catch (error) {
      live.disconnect();
      if (!completer.isCompleted)
        completer.completeError(RustaBaseError.from(error));
    }
    return completer.future;
  }

  Future<AuthResult<T>> signInWithOAuthCode({
    required String provider,
    required String code,
    required String codeVerifier,
    required String redirectUrl,
    Json createData = const {},
    ReadOptions options = const ReadOptions(),
  }) async =>
      _save(
        await rb.request<Json>(
          "$base/auth-with-oauth2",
          options: RequestOptions(
            method: "POST",
            body: {
              "provider": provider,
              "code": code,
              "codeVerifier": codeVerifier,
              "redirectURL": redirectUrl,
              "createData": createData,
            },
            query: readQuery(options),
            headers: options.headers,
            requestKey: options.requestKey,
            autoCancel: options.autoCancel,
          ),
        ),
      );

  Future<AuthResult<T>> refresh({
    ReadOptions options = const ReadOptions(),
  }) async =>
      _save(
        await rb.request<Json>(
          "$base/auth-refresh",
          options: RequestOptions(
            method: "POST",
            query: readQuery(options),
            headers: options.headers,
            requestKey: options.requestKey,
            autoCancel: options.autoCancel,
          ),
        ),
      );

  Future<RustaBase> impersonate(
    String recordId, {
    int durationSeconds = 0,
    ReadOptions options = const ReadOptions(),
  }) async {
    final data = await rb.request<Json>(
      "$base/impersonate/${seg(recordId)}",
      options: RequestOptions(
        method: "POST",
        body: {"duration": durationSeconds},
        query: readQuery(options),
        headers: {...options.headers, "Authorization": rb.session.token},
        requestKey: options.requestKey,
        autoCancel: options.autoCancel,
      ),
    );
    final client = RustaBase(
      rb.baseUrl,
      session: MemorySession(),
      lang: rb.lang,
      httpClientFactory: rb.httpClientFactory,
    );
    final result = _parse(data);
    client.session.set(result.token, result.record);
    return client;
  }

  Future<bool> requestPasswordReset(
    String email, {
    RequestOptions options = const RequestOptions(),
  }) =>
      _post("/request-password-reset", {"email": email}, options);
  Future<bool> confirmPasswordReset(
    String token,
    String password,
    String passwordConfirm, {
    RequestOptions options = const RequestOptions(),
  }) =>
      _post(
          "/confirm-password-reset",
          {
            "token": token,
            "password": password,
            "passwordConfirm": passwordConfirm,
          },
          options);
  Future<bool> requestVerification(
    String email, {
    RequestOptions options = const RequestOptions(),
  }) =>
      _post("/request-verification", {"email": email}, options);
  Future<bool> requestEmailChange(
    String newEmail, {
    RequestOptions options = const RequestOptions(),
  }) =>
      _post("/request-email-change", {"newEmail": newEmail}, options);

  Future<bool> confirmVerification(
    String token, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await _post("/confirm-verification", {"token": token}, options);
    final claims = readClaims(token);
    final current = rb.session.record;
    if (current != null &&
        current["id"] == claims["id"] &&
        current["collectionId"] == claims["collectionId"])
      rb.session.set(rb.session.token, {...current, "verified": true});
    return true;
  }

  Future<bool> confirmEmailChange(
    String token,
    String password, {
    RequestOptions options = const RequestOptions(),
  }) async {
    await _post(
        "/confirm-email-change",
        {
          "token": token,
          "password": password,
        },
        options);
    final claims = readClaims(token);
    final current = rb.session.record;
    if (current != null &&
        current["id"] == claims["id"] &&
        current["collectionId"] == claims["collectionId"]) rb.session.clear();
    return true;
  }

  Future<bool> _post(String suffix, Json body, RequestOptions options) async {
    await rb.request<Object?>(
      "$base$suffix",
      options: options.copyWith(method: "POST", body: body),
    );
    return true;
  }

  AuthResult<T> _save(Json data) {
    final result = _parse(data);
    rb.session.set(result.token, result.record);
    return result;
  }

  AuthResult<T> _parse(Json data) => AuthResult<T>(
        token: data["token"] as String? ?? "",
        record:
            Map<String, dynamic>.from(data["record"] as Map? ?? const {}) as T,
        meta: data["meta"] is Map
            ? Map<String, dynamic>.from(data["meta"] as Map)
            : {},
      );
}
