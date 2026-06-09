import "package:flutter_test/flutter_test.dart";
import "package:hydracam/constants.dart";

void main() {
  test("bundled court fallback data omits release-visible placeholders", () {
    final placeholderPattern = RegExp(
      r"\b(test|testing)\b|addadsa|sada\d*",
      caseSensitive: false,
    );

    for (final entry in groupedCourts.entries) {
      expect(
        entry.value,
        isNotEmpty,
        reason:
            "Bundled sports center '${entry.key}' should not render without courts.",
      );
      expect(
        placeholderPattern.hasMatch(entry.key),
        isFalse,
        reason:
            "Bundled sports center '${entry.key}' looks like placeholder data.",
      );

      for (final court in entry.value) {
        final name = court["name"] ?? "";
        final guid = court["guid"] ?? "";
        expect(name, isNotEmpty);
        expect(guid, isNotEmpty);
        expect(
          placeholderPattern.hasMatch(name),
          isFalse,
          reason: "Bundled court '$name' looks like placeholder data.",
        );
      }
    }
  });
}
