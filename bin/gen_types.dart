// Generates Dart model classes from your RustaBase tables.
//
//   dart run rustabase:gen_types --url https://api.example.com --email admin@x.com --password ...
//   dart run rustabase:gen_types --file schema.json --out lib/rustabase_types.dart
//
// Environment fallbacks: RUSTABASE_URL, RUSTABASE_TOKEN, RUSTABASE_EMAIL,
// RUSTABASE_PASSWORD.

import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;
import "package:rustabase/codegen.dart";

const _help = '''
Usage: dart run rustabase:gen_types [options]

Reads your tables and writes Dart model classes for them.

Options:
  --url <url>          Server address (or RUSTABASE_URL)
  --token <token>      Superuser token (or RUSTABASE_TOKEN)
  --email <email>      Superuser email (or RUSTABASE_EMAIL)
  --password <pass>    Superuser password (or RUSTABASE_PASSWORD)
  --file <path>        Read the schema from an exported JSON file instead
  --out <path>         Output file (default: lib/rustabase_types.dart, "-" for stdout)
  --include-system     Also generate classes for built-in tables
  -h, --help           Show this help
''';

Map<String, String> _parse(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a == "-h" || a == "--help") {
      out["help"] = "1";
    } else if (a == "--include-system") {
      out["include-system"] = "1";
    } else if (a.startsWith("--")) {
      final eq = a.indexOf("=");
      if (eq > 0) {
        out[a.substring(2, eq)] = a.substring(eq + 1);
      } else if (i + 1 < argv.length) {
        out[a.substring(2)] = argv[++i];
      }
    }
  }
  return out;
}

Future<Map<String, dynamic>> _call(http.Response res, String what) async {
  if (res.statusCode >= 400) {
    throw Exception("$what failed [${res.statusCode}]: ${res.body}");
  }
  final data = res.body.isEmpty ? null : jsonDecode(res.body);
  return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
}

Future<List<dynamic>> _schema(Map<String, String> args) async {
  final env = Platform.environment;
  if (args["file"] != null) {
    final Object? data = jsonDecode(await File(args["file"]!).readAsString());
    if (data is List) return data;
    if (data is Map) {
      return (data["items"] ?? data["collections"] ?? const <Object>[]) as List;
    }
    return const [];
  }
  final base = (args["url"] ?? env["RUSTABASE_URL"] ?? "").replaceAll(
    RegExp(r"/+$"),
    "",
  );
  if (base.isEmpty) throw Exception("missing --url (or RUSTABASE_URL)");
  var token = args["token"] ?? env["RUSTABASE_TOKEN"];
  final email = args["email"] ?? env["RUSTABASE_EMAIL"];
  final password = args["password"] ?? env["RUSTABASE_PASSWORD"];
  if (token == null && email != null && password != null) {
    final auth = await _call(
      await http.post(
        Uri.parse("$base/api/collections/_superusers/auth-with-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"identity": email, "password": password}),
      ),
      "sign-in",
    );
    token = auth["token"] as String?;
  }
  if (token == null) {
    throw Exception(
      "missing --token, or --email and --password, of a superuser",
    );
  }
  final items = <dynamic>[];
  for (var page = 1; page < 100; page++) {
    final res = await _call(
      await http.get(
        Uri.parse("$base/api/collections?perPage=200&page=$page"),
        headers: {"Authorization": token},
      ),
      "reading tables",
    );
    items.addAll((res["items"] as List?) ?? const []);
    final total = res["totalPages"];
    if (total is! num || page >= total) break;
  }
  return items;
}

Future<void> main(List<String> argv) async {
  final args = _parse(argv);
  if (args["help"] != null) {
    stdout.write(_help);
    return;
  }
  try {
    final schema = await _schema(args);
    final system = args["include-system"] != null;
    final src = generateDartTypes(schema, includeSystem: system);
    final out = args["out"] ?? "lib/rustabase_types.dart";
    if (out == "-") {
      stdout.write(src);
      return;
    }
    final file = File(out);
    await file.parent.create(recursive: true);
    await file.writeAsString(src);
    final n = schema
        .where((c) => system || (c is Map && c["system"] != true))
        .length;
    stderr.writeln("Wrote classes for $n table(s) to $out");
  } catch (e) {
    stderr.writeln("rustabase: $e");
    exitCode = 1;
  }
}
