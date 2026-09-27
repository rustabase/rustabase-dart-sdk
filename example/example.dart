import "package:rustabase_dart_sdk/rustabase.dart";

Future<void> main() async {
  final rb = createClient("https://my-app.rustabase.net");
  final posts = await rb
      .from("posts")
      .list(options: ListOptions(sort: "-created", perPage: 20));
  for (final post in posts.items) {
    print(post["title"]);
  }
  rb.close();
}
