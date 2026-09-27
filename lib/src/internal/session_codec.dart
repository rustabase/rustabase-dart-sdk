import "dart:convert";

import "../types.dart";
import "token.dart";

/// Formats [value] as an IMF-fixdate (e.g. "Sun, 06 Nov 1994 08:49:37 GMT"),
/// the only date format browsers accept in cookie Expires attributes.
String httpDate(DateTime value) {
  const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, "0");
  return "${weekdays[utc.weekday - 1]}, ${two(utc.day)} "
      "${months[utc.month - 1]} ${utc.year} "
      "${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT";
}

class SessionSnapshot {
  const SessionSnapshot({this.token = "", this.record});

  final String token;
  final Row? record;

  bool sameIdentity(SessionSnapshot other) =>
      token == other.token && identical(record, other.record);

  String serialize() => jsonEncode({"token": token, "record": record});

  static SessionSnapshot deserialize(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException("Session data must be a JSON object.");
    }
    return SessionSnapshot(
      token: decoded["token"] as String? ?? "",
      record: decoded["record"] is Map
          ? Map<String, dynamic>.from(decoded["record"] as Map)
          : null,
    );
  }
}

class SessionCookieCodec {
  const SessionCookieCodec({this.encodedValueBudget = 3500});

  final int encodedValueBudget;

  SessionSnapshot read(String cookieHeader, String name) {
    for (final segment in cookieHeader.split(";")) {
      final separator = segment.indexOf("=");
      if (separator < 0 || segment.substring(0, separator).trim() != name) {
        continue;
      }
      final encoded = segment.substring(separator + 1).trim();
      return SessionSnapshot.deserialize(Uri.decodeComponent(encoded));
    }
    return const SessionSnapshot();
  }

  String write({
    required String name,
    required SessionSnapshot snapshot,
    required String path,
    required bool secure,
    required bool httpOnly,
    required String sameSite,
  }) {
    var encoded = Uri.encodeComponent(snapshot.serialize());
    if (encoded.length > encodedValueBudget) {
      encoded = Uri.encodeComponent(
        SessionSnapshot(token: snapshot.token).serialize(),
      );
    }
    final expiresAt = tokenExpiry(snapshot.token) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final attributes = <String>[
      "Path=$path",
      "Expires=${httpDate(expiresAt)}",
      if (secure) "Secure",
      if (httpOnly) "HttpOnly",
      "SameSite=$sameSite",
    ];
    return "$name=$encoded; ${attributes.join('; ')}";
  }
}
