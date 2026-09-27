# RustaBase Dart SDK

Official Dart and Flutter client for [RustaBase](https://rustabase.com). Its API mirrors the RustaBase JavaScript SDK.

This package is independently structured for RustaBase. Shared HTTP paths and payload names belong to the RustaBase wire protocol; its Dart transport, session persistence, retry policy, and tests are package-specific implementations.

## Install

```sh
dart pub add rustabase_dart_sdk
# or
flutter pub add rustabase_dart_sdk
```

## Quick start

```dart
import "package:rustabase_dart_sdk/rustabase.dart";

final rb = createClient("https://my-app.rustabase.net");

await rb.auth("users").signInWithPassword("me@example.com", "secret");

final page = await rb.from("posts").list(
  options: ListOptions(
    filter: rb.filter("status = {:status}", {"status": "live"}),
    sort: "-created",
  ),
);
final all = await rb.from("posts").all();
final post = await rb.from("posts").get("RECORD_ID");
final latest = await rb.from("posts").first("featured = true");

final created = await rb.from("posts").create({"title": "Hello"});
await rb.from("posts").update(created["id"].toString(), {"title": "Hello again"});
await rb.from("posts").remove(created["id"].toString());

final stop = await rb.from("posts").subscribe("*", (event) {
  print("${event.action}: ${event.record}");
});
await stop();
```

## Files

Dart uses `http.MultipartFile` for uploads:

```dart
import "package:http/http.dart" as http;

await rb.from("posts").create(
  {"title": "Hello"},
  files: [http.MultipartFile.fromString("attachment", "content", filename: "note.txt")],
);

final url = rb.files.url(record, record["avatar"].toString(), thumb: "100x100");
final token = await rb.files.token();
```

## Sessions

`MemorySession` is the default. Use `AsyncSession` with any Flutter persistence package:

```dart
final session = AsyncSession(
  initial: await storage.read("rb_session"),
  save: (value) => storage.write("rb_session", value),
  clearStorage: () => storage.remove("rb_session"),
);
final rb = createClient(url, session: session);
```

The session exposes `token`, `record`, `isValid`, `isSuperuser`, `isUser`, and the `onChange` stream. `rb.signOut()` clears it and cancels pending requests. Cookie helpers are available for server-rendered Dart applications.

## Authentication

```dart
final users = rb.auth("users");
await users.signInWithPassword(email, password, keepAlive: 1800);
final otp = await users.requestOtp(email);
await users.signInWithOtp(otp["otpId"]!, "123456");
await users.refresh();
await users.methods();

await users.signInWithOAuth(
  provider: "google",
  openUrl: (url) => launchUrl(url),
);
```

Password reset, verification, email-change, OAuth code, and impersonation methods use the same names as the JavaScript SDK.

## Batch writes

```dart
final batch = rb.batch();
batch.from("posts").create({"title": "A"});
batch.from("posts").update("id1", {"title": "B"});
batch.from("posts").upsert({"id": "id2", "title": "C"});
batch.from("comments").remove("id3");
final results = await batch.send();
```

## Errors and hooks

All failures throw `RustaBaseError`, exposing `status`, `data`, `fieldErrors`, `cancelled`, and `url`.

```dart
rb.onRequest = (request) => request.copyWith(
  headers: {...request.headers, "X-Trace": "1"},
);
rb.onResponse = (response, data) => data;
```

Duplicate requests use newest-request-wins semantics by default. Pass `RequestOptions(autoCancel: false)`, disable `rb.autoCancel`, or call `rb.cancel(key)` / `rb.cancelAll()`.

## Admin

Superuser tools are grouped under `rb.admin`: `collections`, `settings`, `logs`, `backups`, `crons`, `apiKeys`, `webhooks`, `functions`, `rls`, and `sql()`.

## Version 1 API

Version 1 establishes the RustaBase API with `from()`, `session`, `batch()`, and `RustaBaseError`.

## License

MIT
