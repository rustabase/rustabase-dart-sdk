import "dart:convert";

import "package:http/http.dart" as http;

import "../client.dart";
import "../internal/encode.dart";
import "../types.dart";

class Batch {
  Batch(this.rb);
  final RustaBase rb;
  final List<_Step> _steps = [];
  int get size => _steps.length;
  BatchTable from(String collection) => BatchTable(this, collection);

  /// Drops all queued writes without sending them.
  void clear() => _steps.clear();

  Future<List<BatchResult>> send({
    RequestOptions options = const RequestOptions(),
  }) async {
    if (_steps.isEmpty)
      throw StateError("The batch is empty — queue at least one write.");
    final envelope = _BatchEnvelope.fromSteps(_steps);
    final result = await rb.request<List<dynamic>>(
      "/api/batch",
      options: RequestOptions(
        method: "POST",
        body: const <String, dynamic>{},
        files: envelope.parts,
        query: options.query,
        headers: options.headers,
        requestKey: options.requestKey,
        autoCancel: options.autoCancel,
      ),
    );
    // The server processed these steps; keeping them would resend duplicates
    // on the next send().
    _steps.clear();
    return result
        .map(
          (item) =>
              BatchResult.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}

class _BatchEnvelope {
  const _BatchEnvelope(this.parts);

  final List<http.MultipartFile> parts;

  factory _BatchEnvelope.fromSteps(List<_Step> steps) {
    final descriptions = <Json>[];
    final parts = <http.MultipartFile>[];
    for (final indexed in steps.indexed) {
      final (index, step) = indexed;
      descriptions.add(step.describe());
      parts.addAll(step.fileParts(index));
    }
    parts.add(
      http.MultipartFile.fromString(
        "@jsonPayload",
        const JsonEncoder().convert({"requests": descriptions}),
        filename: "batch.json",
      ),
    );
    return _BatchEnvelope(parts);
  }
}

class BatchTable {
  BatchTable(this.batch, this.collection);
  final Batch batch;
  final String collection;
  String get path => "/api/collections/${seg(collection)}/records";
  void create(
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) =>
      batch._steps.add(_Step("POST", path, data, files, options));
  void update(
    String id,
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) =>
      batch._steps.add(
        _Step("PATCH", "$path/${seg(id)}", data, files, options),
      );
  void upsert(
    Json data, {
    List<http.MultipartFile> files = const [],
    ReadOptions options = const ReadOptions(),
  }) =>
      batch._steps.add(_Step("PUT", path, data, files, options));
  void remove(String id, {ReadOptions options = const ReadOptions()}) =>
      batch._steps
          .add(_Step("DELETE", "$path/${seg(id)}", {}, const [], options));
}

class _Step {
  const _Step(this.method, this.url, this.body, this.files, this.options);
  final String method;
  final String url;
  final Json body;
  final List<http.MultipartFile> files;
  final ReadOptions options;

  Json describe() => {
        "method": method,
        "url": withQuery(url, options.query),
        "headers": options.headers,
        "body": body,
      };

  Iterable<http.MultipartFile> fileParts(int index) sync* {
    for (final file in files) {
      yield http.MultipartFile(
        "requests.$index.${file.field}",
        file.finalize(),
        file.length,
        filename: file.filename,
        contentType: file.contentType,
      );
    }
  }
}
