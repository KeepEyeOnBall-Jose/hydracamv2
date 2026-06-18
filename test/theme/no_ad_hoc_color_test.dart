import "dart:io";

import "package:flutter_test/flutter_test.dart";

final _directColorPattern = RegExp(
  r"\bColors\.(?!transparent\b)|\bColor\(\s*0x|\bColor\.fromARGB|\bColor\.fromRGBO",
);

const _allowedThemeFiles = <String, String>{
  "lib/app_theme.dart": "centralized theme token definitions",
};

const _allowedColorUsages = <String, String>{
  "lib/widgets/camera_level_overlay.dart|color: Colors.black.withValues(alpha: 0.72),":
      "camera sensor overlay needs a dark readable scrim over live preview",
  "lib/widgets/camera_level_overlay.dart|color: Colors.white,":
      "camera sensor overlay measurement text must remain readable on the scrim",
  "lib/widgets/camera_level_overlay.dart|DeviceLevelZone.green => Colors.green,":
      "camera sensor calibration uses traffic-light level feedback",
  "lib/widgets/camera_level_overlay.dart|DeviceLevelZone.amber => Colors.amber,":
      "camera sensor calibration uses traffic-light warning feedback",
  "lib/widgets/camera_level_overlay.dart|DeviceLevelZone.red => Colors.red,":
      "camera sensor calibration uses traffic-light danger feedback",
  "lib/widgets/camera_level_overlay.dart|DeviceLevelZone.unavailable => Colors.white70,":
      "camera sensor unavailable state must stay visible over live preview",
};

void main() {
  test("source scanner ignores comments and string literals", () {
    final violations = findAdHocColorViolationsInLines(
      "lib/fixture.dart",
      [
        'final label = "Colors.red is not executable";',
        "final raw = r'Color(0xFF00AA00) is copy';",
        "// Colors.blue is a comment",
        "/* Colors.purple is a block comment */",
        "final illegal = Colors.green;",
        "final illegalHex = Color(0xFF00AA00);",
      ],
    );

    expect(violations, [
      "lib/fixture.dart:5: final illegal = Colors.green;",
      "lib/fixture.dart:6: final illegalHex = Color(0xFF00AA00);",
    ]);
  });

  test("every direct color exception has a named reason", () {
    expect(_allowedThemeFiles.values, everyElement(isNotEmpty));
    expect(_allowedColorUsages.values, everyElement(isNotEmpty));
  });

  test("UI colors are centralized in AppTheme", () {
    final repoRoot = Directory.current;
    final libRoot = Directory("${repoRoot.path}/lib");
    final violations = <String>[];

    for (final entity in libRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith(".dart")) {
        continue;
      }

      final relativePath =
          entity.path.substring(repoRoot.path.length + 1).replaceAll("\\", "/");
      if (_allowedThemeFiles.containsKey(relativePath)) {
        continue;
      }

      violations.addAll(
        findAdHocColorViolationsInLines(
          relativePath,
          entity.readAsLinesSync(),
        ),
      );
    }

    expect(
      violations,
      isEmpty,
      reason:
          "Use AppTheme semantic color roles instead of direct UI colors.\n${violations.join("\n")}",
    );
  });
}

List<String> findAdHocColorViolationsInLines(
  String relativePath,
  List<String> lines,
) {
  final violations = <String>[];
  final codeLines = _stripCommentsAndStrings(lines);
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final codeLine = codeLines[index];
    final trimmedLine = line.trim();
    final exceptionKey = "$relativePath|$trimmedLine";
    if (_allowedColorUsages.containsKey(exceptionKey)) {
      continue;
    }
    if (_directColorPattern.hasMatch(codeLine)) {
      violations.add("$relativePath:${index + 1}: $trimmedLine");
    }
  }
  return violations;
}

List<String> _stripCommentsAndStrings(List<String> lines) {
  final strippedLines = <String>[];
  var inBlockComment = false;
  String? stringDelimiter;
  var isTripleQuotedString = false;
  var isRawString = false;

  for (final line in lines) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < line.length) {
      if (inBlockComment) {
        if (_startsWith(line, "*/", index)) {
          inBlockComment = false;
          index += 2;
        } else {
          index += 1;
        }
        continue;
      }

      if (stringDelimiter != null) {
        final tripleDelimiter = _tripleDelimiter(stringDelimiter);
        if (isTripleQuotedString && _startsWith(line, tripleDelimiter, index)) {
          stringDelimiter = null;
          isTripleQuotedString = false;
          isRawString = false;
          index += tripleDelimiter.length;
          continue;
        }

        if (!isTripleQuotedString && line[index] == stringDelimiter) {
          stringDelimiter = null;
          isRawString = false;
          index += 1;
          continue;
        }

        if (!isRawString && line[index] == r"\") {
          index += 2;
        } else {
          index += 1;
        }
        continue;
      }

      if (_startsWith(line, "//", index)) {
        break;
      }
      if (_startsWith(line, "/*", index)) {
        inBlockComment = true;
        index += 2;
        continue;
      }

      final rawStringDelimiter = _rawStringDelimiterAt(line, index);
      if (rawStringDelimiter != null) {
        stringDelimiter = rawStringDelimiter.delimiter;
        isTripleQuotedString = rawStringDelimiter.isTripleQuoted;
        isRawString = true;
        index += rawStringDelimiter.openingLength;
        continue;
      }

      if (line[index] == '"' || line[index] == "'") {
        final delimiter = line[index];
        final tripleDelimiter = _tripleDelimiter(delimiter);
        stringDelimiter = delimiter;
        isTripleQuotedString = _startsWith(line, tripleDelimiter, index);
        isRawString = false;
        index += isTripleQuotedString ? tripleDelimiter.length : 1;
        continue;
      }

      buffer.write(line[index]);
      index += 1;
    }

    strippedLines.add(buffer.toString());
  }

  return strippedLines;
}

bool _startsWith(String source, String pattern, int index) {
  return source.length >= index + pattern.length &&
      source.substring(index, index + pattern.length) == pattern;
}

String _tripleDelimiter(String delimiter) {
  return delimiter + delimiter + delimiter;
}

_RawStringDelimiter? _rawStringDelimiterAt(String line, int index) {
  if (line[index] != "r" || line.length <= index + 1) {
    return null;
  }

  final delimiter = line[index + 1];
  if (delimiter != '"' && delimiter != "'") {
    return null;
  }

  final tripleDelimiter = _tripleDelimiter(delimiter);
  final isTripleQuoted = _startsWith(line, tripleDelimiter, index + 1);
  return _RawStringDelimiter(
    delimiter: delimiter,
    isTripleQuoted: isTripleQuoted,
    openingLength: isTripleQuoted ? 1 + tripleDelimiter.length : 2,
  );
}

class _RawStringDelimiter {
  const _RawStringDelimiter({
    required this.delimiter,
    required this.isTripleQuoted,
    required this.openingLength,
  });

  final String delimiter;
  final bool isTripleQuoted;
  final int openingLength;
}
