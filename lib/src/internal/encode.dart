import "dart:convert";

String joinUrl(String base, String path) {
  if (path.isEmpty) return base;
  return "${base.replaceFirst(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}";
}

String seg(String value) => Uri.encodeComponent(value);

String stringifyParam(Object? value) {
  if (value is DateTime)
    return value.toUtc().toIso8601String().replaceFirst("T", " ");
  if (value is Map || value is List) return jsonEncode(value);
  return value.toString();
}

String toQueryString(Map<String, dynamic>? query) {
  if (query == null) return "";
  final parts = <String>[];
  query.forEach((key, raw) {
    if (raw == null) return;
    final values = raw is List ? raw : [raw];
    for (final value in values) {
      parts.add(
        "${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(stringifyParam(value))}",
      );
    }
  });
  return parts.join("&");
}

String withQuery(String url, Map<String, dynamic>? query) {
  final encoded = toQueryString(query);
  if (encoded.isEmpty) return url;
  return "$url${url.contains('?') ? '&' : '?'}$encoded";
}

String bindFilter(String expression, [Map<String, dynamic>? params]) {
  if (params == null) return expression;
  final output = StringBuffer();
  var cursor = 0;
  for (final match in RegExp(r"\{:\s*([\w]+)\}").allMatches(expression)) {
    output.write(expression.substring(cursor, match.start));
    final name = match.group(1);
    output.write(name != null && params.containsKey(name)
        ? _filterLiteral(params[name])
        : match.group(0));
    cursor = match.end;
  }
  output.write(expression.substring(cursor));
  return output.toString();
}

String _filterLiteral(Object? value) {
  if (value == null) return "null";
  if (value is num || value is bool) return value.toString();
  if (value is DateTime)
    return jsonEncode(value.toUtc().toIso8601String().replaceFirst("T", " "));
  if (value is String) return jsonEncode(value);
  final encoded = jsonEncode(value);
  return encoded.startsWith("[") || encoded.startsWith("{")
      ? jsonEncode(encoded)
      : encoded;
}
