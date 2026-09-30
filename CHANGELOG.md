## 1.0.1

- Hardened realtime: a failed connect or initial sync now surfaces as a
  `RustaBaseError`, tears down the SSE stream, and retries instead of
  throwing an unhandled async error; subscriber callbacks can no longer
  kill the event stream.
- Added a `timeout` to `signInWithOAuth` (default 5 minutes) so an
  abandoned provider flow fails cleanly instead of hanging forever and
  leaking the realtime connection.
- Updating the signed-in record no longer crashes when the server returns
  a non-map `expand` value.
- Restoring a session from corrupt storage now clears the session instead
  of crashing with a cast error.

## 1.0.0

- Rewrote the SDK around the same public API as the RustaBase JavaScript SDK.
- Added `from()`, `auth()`, `session`, `batch()`, `RustaBaseError`, hooks, cancellation, and token keep-alive.
- Added JavaScript-parity CRUD, authentication, files, realtime, batch, and superuser administration APIs.
- Implemented an independent Dart transport pipeline, request ledger, session codec, and reconnect policy.
- Established the clean RustaBase 1.x public API. This is a breaking release from earlier previews.
