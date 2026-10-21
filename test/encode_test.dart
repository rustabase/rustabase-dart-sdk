import "package:rustabase/src/internal/encode.dart";
import "package:test/test.dart";

void main() {
  test("adds query parameters before a URL fragment", () {
    expect(
      withQuery("https://example.test/items#section?details", {"page": 2}),
      "https://example.test/items?page=2#section?details",
    );
  });

  test("preserves existing query parameters before a fragment", () {
    expect(
      withQuery("/items?sort=name#top", {"page": 2}),
      "/items?sort=name&page=2#top",
    );
  });

  test("does not add a redundant separator to an empty query", () {
    expect(withQuery("/items?", {"page": 2}), "/items?page=2");
    expect(
      withQuery("/items?sort=name&", {"page": 2}),
      "/items?sort=name&page=2",
    );
  });

  test("leaves URLs unchanged without query values", () {
    expect(withQuery("/items?#top", {"page": null}), "/items?#top");
  });
}
