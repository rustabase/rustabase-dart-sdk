import "dart:async";
import "../internal/session_codec.dart";
import "../internal/token.dart";
import "../protocol.dart";
import "../types.dart";

class SessionEvent {
  const SessionEvent(this.token, this.record);
  final String token;
  final Row? record;
}

class Session {
  SessionSnapshot _snapshot = const SessionSnapshot();
  final StreamController<SessionEvent> _changes =
      StreamController<SessionEvent>.broadcast();

  String get token => _snapshot.token;
  Row? get record => _snapshot.record;
  bool get isValid => !tokenExpired(token);
  bool get isSuperuser {
    final claims = readClaims(token);
    if (claims["type"] != "auth") return false;
    return record?["collectionName"] == superusers ||
        claims["collectionId"] == superusersId;
  }

  bool get isUser => readClaims(token)["type"] == "auth" && !isSuperuser;
  Stream<SessionEvent> get onChange => _changes.stream;

  void set(String token, [Row? record]) {
    final next = SessionSnapshot(token: token, record: record);
    if (_snapshot.sameIdentity(next)) return;
    _snapshot = next;
    _changes.add(SessionEvent(next.token, next.record));
  }

  void clear() => set("", null);

  void loadCookie(String cookieHeader, {String name = sessionKey}) {
    try {
      final restored = const SessionCookieCodec().read(cookieHeader, name);
      set(restored.token, restored.record);
    } on FormatException {
      clear();
    }
  }

  String toCookie({
    String name = sessionKey,
    String path = "/",
    bool secure = true,
    bool httpOnly = true,
    String sameSite = "Strict",
  }) {
    return const SessionCookieCodec().write(
      name: name,
      snapshot: _snapshot,
      path: path,
      secure: secure,
      httpOnly: httpOnly,
      sameSite: sameSite,
    );
  }
}

class MemorySession extends Session {}
