import "dart:convert";

Map<String, dynamic> readClaims(String token) {
  final separator = token.indexOf(".");
  if (separator < 0) return {};
  final nextSeparator = token.indexOf(".", separator + 1);
  final end = nextSeparator < 0 ? token.length : nextSeparator;
  final payload = token.substring(separator + 1, end);
  if (payload.isEmpty) return {};
  try {
    final raw = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
    final value = jsonDecode(raw);
    return value is Map ? Map<String, dynamic>.from(value) : {};
  } catch (_) {
    return {};
  }
}

DateTime? tokenExpiry(String token) {
  final value = readClaims(token)["exp"];
  if (value is! num || !value.isFinite) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    (value * Duration.millisecondsPerSecond).round(),
    isUtc: true,
  );
}

bool tokenExpired(String token, [int leewaySeconds = 0]) {
  final claims = readClaims(token);
  if (claims.isEmpty) return true;
  if (!claims.containsKey("exp") || claims["exp"] == null) return false;
  final expiry = tokenExpiry(token);
  if (expiry == null) return true;
  return !expiry.subtract(Duration(seconds: leewaySeconds)).isAfter(
        DateTime.now().toUtc(),
      );
}
