# Authentication

Create a client and select the authentication collection:

```dart
final rb = createClient("https://my-app.rustabase.net");
final users = rb.auth("users");
await users.signInWithPassword("me@example.com", "secret");
```

The client stores the returned token and record in its session. Call `rb.signOut()` to clear the session and cancel pending requests.

Use `AsyncSession` with secure application storage when credentials must survive restarts. Never write tokens to logs or source control.