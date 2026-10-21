import "dart:io";

import "package:test/test.dart";

void main() {
  for (final args in [
    ["--file"],
    ["--file", "--out", "-"],
    ["--file="],
  ]) {
    test("rejects missing option value: ${args.join(' ')}", () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        "run",
        "bin/gen_types.dart",
        ...args,
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains("missing value for --file"));
      expect(result.stderr, isNot(contains("PathNotFoundException")));
      expect(result.stdout, isEmpty);
    });
  }

  test("preserves equals signs in inline values and supports stdout", () async {
    final dir = await Directory.systemTemp.createTemp("rb_cli");
    addTearDown(() => dir.delete(recursive: true));
    final file = File("${dir.path}/schema=export.json");
    await file.writeAsString('[{"name":"notes","fields":[]}]');
    final result = await Process.run(Platform.resolvedExecutable, [
      "run",
      "bin/gen_types.dart",
      "--file=${file.path}",
      "--out",
      "-",
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains("class Notes {"));
  });
}
