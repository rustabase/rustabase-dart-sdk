import "dart:async";

import "../internal/session_codec.dart";
import "session.dart";

typedef SaveSession = FutureOr<void> Function(String data);
typedef ClearSession = FutureOr<void> Function();

class AsyncSession extends Session {
  AsyncSession({required this.save, this.clearStorage, String? initial}) {
    if (initial != null && initial.isNotEmpty) {
      try {
        final snapshot = SessionSnapshot.deserialize(initial);
        super.set(snapshot.token, snapshot.record);
      } on FormatException {
        super.clear();
      }
    }
  }

  final SaveSession save;
  final ClearSession? clearStorage;
  Future<void> _queue = Future.value();

  @override
  void set(String token, [Map<String, dynamic>? record]) {
    super.set(token, record);
    final data = SessionSnapshot(token: token, record: record).serialize();
    _queue = _queue.then((_) async => save(data));
  }

  @override
  void clear() {
    super.clear();
    final clear = clearStorage;
    _queue = _queue.then(
      (_) async => clear != null ? clear() : save(""),
    );
  }
}
