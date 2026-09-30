import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:rustabase/rustabase.dart";
import "package:test/test.dart";

String token(Map<String, dynamic> claims) =>
    "x.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.y";

void main() {
  group("client", () {
    test("builds URLs and binds filters", () {
      final rb = createClient("https://example.test/");
      expect(rb.url("/api/health"), "https://example.test/api/health");
      expect(
        rb.filter("name = {:name} && live = {:live}", {
          "name": "A",
          "live": true,
        }),
        'name = "A" && live = true',
      );
    });

    test("sends auth, language, query, and hooks", () async {
      late http.Request captured;
      final session = MemorySession()
        ..set(token({"exp": 4102444800}), {"id": "u1"});
      final rb = createClient(
        "https://example.test",
        session: session,
        httpClientFactory: () => MockClient((request) async {
          captured = request;
          return http.Response('{"ok":true}', 200);
        }),
      );
      rb.onRequest = (request) =>
          request.copyWith(headers: {...request.headers, "X-Trace": "1"});
      rb.onResponse = (_, data) => {
            ...data as Map<String, dynamic>,
            "hooked": true,
          };
      final result = await rb.request<Json>(
        "/items",
        options: const RequestOptions(
          query: {
            "tag": ["a", "b"],
          },
        ),
      );
      expect(captured.url.queryParametersAll["tag"], ["a", "b"]);
      expect(captured.headers["authorization"], session.token);
      expect(captured.headers["accept-language"], "en-US");
      expect(captured.headers["x-trace"], "1");
      expect(result["hooked"], true);
    });

    test("normalizes API errors", () async {
      final rb = createClient(
        "https://example.test",
        httpClientFactory: () => MockClient(
          (_) async => http.Response(
            '{"message":"Invalid","data":{"email":{"code":"bad"}}}',
            400,
          ),
        ),
      );
      await expectLater(
        rb.health(),
        throwsA(
          isA<RustaBaseError>().having((e) => e.status, "status", 400).having(
                (e) => e.fieldErrors.containsKey("email"),
                "fieldErrors",
                true,
              ),
        ),
      );
    });
  });

  test("CRUD and auth mirror JavaScript paths", () async {
    final requests = <http.Request>[];
    final rb = createClient(
      "https://example.test",
      httpClientFactory: () => MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith("auth-with-password"))
          return http.Response(
            '{"token":"abc","record":{"id":"u1","collectionName":"users"}}',
            200,
          );
        if (request.method == "GET" && request.url.path.endsWith("/records"))
          return http.Response(
            '{"page":1,"perPage":30,"totalItems":1,"totalPages":1,"items":[{"id":"p1"}]}',
            200,
          );
        return http.Response('{"id":"p1","title":"Hello"}', 200);
      }),
    );
    expect((await rb.from("posts").list()).items.first["id"], "p1");
    expect(
      (await rb.from("posts").create({"title": "Hello"}))["title"],
      "Hello",
    );
    final auth =
        await rb.auth("users").signInWithPassword("me@example.com", "secret");
    expect(auth.record["id"], "u1");
    expect(rb.session.token, "abc");
    expect(
      requests.map((r) => r.url.path),
      contains("/api/collections/users/auth-with-password"),
    );
  });

  test("session token helpers and cookies", () {
    final session = MemorySession();
    session.set(
      token({"type": "auth", "collectionId": superusersId, "exp": 4102444800}),
      {"id": "admin"},
    );
    expect(session.isValid, true);
    expect(session.isSuperuser, true);
    final cookie = session.toCookie(secure: false, httpOnly: false);
    final restored = MemorySession()..loadCookie(cookie);
    expect(restored.token, session.token);
    expect(restored.record?["id"], "admin");
  });

  test("large session cookies preserve credentials without oversized records",
      () {
    final session = MemorySession();
    session.set(
      token({"exp": 4102444800}),
      {"id": "u1", "profile": List.filled(5000, "x").join()},
    );
    final cookie = session.toCookie(secure: false, httpOnly: false);
    final restored = MemorySession()..loadCookie(cookie);
    expect(restored.token, session.token);
    expect(restored.record, isNull);
  });

  test("async sessions serialize writes in order", () async {
    final saved = <String>[];
    final session = AsyncSession(save: (value) async => saved.add(value));
    session.set("first", {"id": "u1"});
    session.set("second", {"id": "u2"});
    await Future<void>.delayed(Duration.zero);
    expect(saved, hasLength(2));
    expect(saved.last, contains('"token":"second"'));
  });

  test("files and batches follow the RustaBase wire protocol", () async {
    late http.BaseRequest captured;
    final rb = createClient(
      "https://example.test",
      httpClientFactory: () => MockClient((request) async {
        captured = request;
        if (request.url.path == "/api/batch")
          return http.Response('[{"status":200,"body":{"id":"p1"}}]', 200);
        return http.Response('{"token":"file-token"}', 200);
      }),
    );
    expect(
      rb.files.url({"id": "p1", "collectionName": "posts"}, "a b.png"),
      "https://example.test/api/files/posts/p1/a%20b.png",
    );
    expect(await rb.files.token(), "file-token");
    final batch = rb.batch();
    batch.from("posts").create({"title": "A"});
    expect(batch.size, 1);
    expect((await batch.send()).first.status, 200);
    expect(captured.headers["content-type"], startsWith("multipart/form-data"));
    expect(captured, isA<http.Request>());
    final body = (captured as http.Request).body;
    expect(body, contains("@jsonPayload"));
    expect(body, contains('"method":"POST"'));
  });

  group("fixes", () {
    test("cookie Expires uses the HTTP date format", () {
      final session = MemorySession()
        ..set(token({"exp": 4102444800}), {"id": "u1"});
      final cookie = session.toCookie(secure: false, httpOnly: false);
      expect(cookie, contains("Expires=Fri, 01 Jan 2100 00:00:00 GMT"));
    });

    test("malformed UTF-8 response bodies decode instead of throwing",
        () async {
      final rb = createClient(
        "https://example.test",
        httpClientFactory: () => MockClient(
          (_) async => http.Response.bytes([0x61, 0xFF, 0x62], 200),
        ),
      );
      expect(await rb.request<Object?>("/x"), isA<String>());
    });

    test("wrapping an error fills in a missing url", () {
      final original = RustaBaseError(status: 500);
      final wrapped = RustaBaseError.from(original, url: "https://x.test/y");
      expect(wrapped.url, "https://x.test/y");
      expect(wrapped.status, 500);
      expect(identical(RustaBaseError.from(wrapped), wrapped), true);
    });

    test("file urls reject blank record ids and collections", () {
      final rb = createClient("https://example.test");
      expect(rb.files.url({"id": " ", "collectionName": "posts"}, "a.png"), "");
      expect(rb.files.url({"id": "p1", "collectionName": " "}, "a.png"), "");
    });

    test("batches clear queued steps after a successful send", () async {
      final rb = createClient(
        "https://example.test",
        httpClientFactory: () => MockClient(
          (_) async => http.Response('[{"status":200,"body":{}}]', 200),
        ),
      );
      final batch = rb.batch();
      batch.from("posts").create({"title": "A"});
      await batch.send();
      expect(batch.size, 0);
      batch.from("posts").create({"title": "B"});
      batch.clear();
      expect(batch.size, 0);
    });

    test("async sessions keep saving after a failed write", () async {
      var calls = 0;
      final session = AsyncSession(
        save: (value) async {
          calls++;
          if (calls == 1) throw StateError("disk full");
        },
      );
      session.set("first", null);
      session.set("second", null);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
    });

    test("loading a cookie with bad percent-encoding clears the session", () {
      final session = MemorySession()..set("tok", {"id": "u1"});
      session.loadCookie("rb_session=%E0%A4%A");
      expect(session.token, "");
    });

    test("a failed realtime connect surfaces as a RustaBaseError", () async {
      final rb = createClient(
        "https://example.test",
        httpClientFactory: () => MockClient.streaming(
          (request, bodyStream) async => http.StreamedResponse(
            Stream.value(utf8.encode("nope")),
            500,
          ),
        ),
      );
      await expectLater(
        rb.realtime.subscribe("posts/*", (_) {}),
        throwsA(isA<RustaBaseError>()),
      );
      expect(rb.realtime.isConnected, false);
    });

    test("updating the signed-in record tolerates a non-map expand", () async {
      final session = MemorySession()
        ..set(
          token({"exp": 4102444800}),
          {"id": "u1", "collectionName": "users"},
        );
      final rb = createClient(
        "https://example.test",
        session: session,
        httpClientFactory: () => MockClient(
          (_) async => http.Response(
            '{"id":"u1","name":"New","expand":"oops"}',
            200,
          ),
        ),
      );
      await rb.auth("users").update("u1", {"name": "New"});
      expect(rb.session.record?["name"], "New");
      // The non-map expand is dropped instead of crashing the update.
      expect(rb.session.record?["expand"], <String, dynamic>{});
    });

    test("OAuth sign-in times out instead of hanging forever", () async {
      final sse = StreamController<List<int>>();
      final rb = createClient(
        "https://example.test",
        httpClientFactory: () => MockClient.streaming((request, body) async {
          if (request.method == "GET" &&
              request.url.path.endsWith("/api/realtime")) {
            return http.StreamedResponse(sse.stream, 200);
          }
          if (request.url.path.endsWith("auth-methods")) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(
                '{"oauth2":{"providers":[{"name":"google",'
                '"authURL":"https://accounts.google.com/o/oauth2/auth"}]}}',
              )),
              200,
              headers: {"content-type": "application/json"},
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode("{}")),
            200,
            headers: {"content-type": "application/json"},
          );
        }),
      );
      addTearDown(sse.close);
      sse.add(utf8.encode("event: RB_CONNECT\nid: client1\ndata: {}\n\n"));
      await expectLater(
        rb.auth().signInWithOAuth(
              provider: "google",
              openUrl: (_) async {},
              timeout: const Duration(milliseconds: 50),
            ),
        throwsA(isA<RustaBaseError>()),
      );
    });

    test(
        "restoring a session with a corrupt payload clears instead of crashing",
        () {
      final session = AsyncSession(
        initial: '{"token":123}',
        save: (_) async {},
      );
      expect(session.token, "");
    });
  });
}
