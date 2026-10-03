import "dart:io";

import "package:rustabase/codegen.dart";
import "package:test/test.dart";

final schema = <Map<String, dynamic>>[
  {
    "name": "blog_posts",
    "type": "base",
    "fields": [
      {"name": "id", "type": "text", "system": true},
      {"name": "title", "type": "text", "required": true},
      {"name": "views", "type": "number"},
      {"name": "published", "type": "bool"},
      {
        "name": "tags",
        "type": "select",
        "options": {
          "maxSelect": 3,
          "values": ["a", "b"],
        },
      },
      {"name": "author", "type": "relation", "maxSelect": 1},
      {"name": "meta", "type": "json"},
      {"name": "where", "type": "geoPoint"},
      {"name": "class", "type": "text"},
      {"name": "note", "type": "text", "hidden": true},
    ],
  },
  {
    "name": "users",
    "type": "auth",
    "fields": [
      {"name": "password", "type": "password"},
    ],
  },
  {"name": "_superusers", "type": "auth", "system": true, "fields": <Object>[]},
];

void main() {
  final out = generateDartTypes(schema);

  test("maps field types", () {
    expect(out, contains("class BlogPosts {"));
    expect(out, contains("  final String title;"));
    expect(out, contains("  final num views;"));
    expect(out, contains("  final bool published;"));
    expect(out, contains("  final List<String> tags;"));
    expect(out, contains("  final String author;"));
    expect(out, contains("  final Object? meta;"));
    expect(out, contains("  final Map<String, num> where;"));
    expect(out, contains('static const tableName = "blog_posts";'));
  });

  test("escapes keywords and hides secrets", () {
    expect(out, contains("  final String class_;"));
    expect(out, isNot(contains("note")));
    expect(out, isNot(contains("password")));
    expect(out, contains("class Users {"));
    expect(out, contains("  final String id;"));
  });

  test("skips system tables unless asked", () {
    expect(out, isNot(contains("Superusers")));
    expect(
      generateDartTypes(schema, includeSystem: true),
      contains("class Superusers {"),
    );
  });

  test("names", () {
    expect(pascalCase("blog_posts"), "BlogPosts");
    expect(camelCase("created_at"), "createdAt");
    expect(camelCase("2fa"), "f2fa");
  });

  test("generated code compiles and round-trips", () async {
    final dir = await Directory.systemTemp.createTemp("rb_codegen");
    await File("${dir.path}/types.dart").writeAsString(out);
    await File("${dir.path}/main.dart").writeAsString(r'''
import "types.dart";
void main() {
  final p = BlogPosts.fromJson({"id": "x", "title": "t", "tags": ["a"], "views": 2});
  if (p.title != "t" || p.tags.first != "a" || p.views != 2) throw "bad";
  if (p.toJson()["title"] != "t" || rustabaseTables["users"] == null) throw "bad";
  print("ok");
}
''');
    final r = await Process.run(Platform.resolvedExecutable, [
      "run",
      "${dir.path}/main.dart",
    ]);
    expect(r.stdout.toString().trim(), "ok", reason: r.stderr.toString());
  });
}
