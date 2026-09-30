# Realtime subscriptions

Subscribe to all changes in a collection:

```dart
final stop = await rb.from("posts").subscribe("*", (event) {
  print("${event.action}: ${event.record}");
});
```

Call the returned function to stop the subscription:

```dart
await stop();
```

The SDK reconnects interrupted streams with bounded exponential backoff and jitter. Signing out closes active realtime connections.