import "../client.dart";
import "../internal/encode.dart";
import "../types.dart";

class Files {
  const Files(this.rb);
  final RustaBase rb;

  String url(
    Row? record,
    String filename, {
    String? thumb,
    bool download = false,
    String? token,
    Json query = const {},
  }) {
    final collection = record?["collectionId"] ?? record?["collectionName"];
    final recordId = record?["id"]?.toString();
    filename = filename.trim();
    if (filename.isEmpty || recordId == null || collection == null) return "";
    return withQuery(
      rb.url(
        "/api/files/${seg(collection.toString())}/${seg(recordId)}/${seg(filename)}",
      ),
      {
        if (thumb != null) "thumb": thumb,
        if (download) "download": true,
        if (token != null) "token": token,
        ...query,
      },
    );
  }

  Future<String> token({
    RequestOptions options = const RequestOptions(),
  }) async {
    final result = await rb.request<Json>(
      "/api/files/token",
      options: options.copyWith(method: "POST"),
    );
    return result["token"] as String? ?? "";
  }
}
