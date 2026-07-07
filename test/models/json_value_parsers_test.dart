import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/json_value_parsers.dart";

void main() {
  group("toDoubleOrNull", () {
    test("passes a double through unchanged", () {
      expect(toDoubleOrNull(1.5), 1.5);
    });

    test("widens an int to a double", () {
      expect(toDoubleOrNull(2), 2.0);
    });

    test("parses a numeric string", () {
      expect(toDoubleOrNull("1.5"), 1.5);
    });

    test("returns null for a non-numeric string", () {
      expect(toDoubleOrNull("x"), isNull);
    });

    test("returns null for null", () {
      expect(toDoubleOrNull(null), isNull);
    });

    test("returns null for a bool", () {
      expect(toDoubleOrNull(true), isNull);
    });
  });

  group("toIntOrNull", () {
    test("passes an int through unchanged", () {
      expect(toIntOrNull(7), 7);
    });

    test("truncates a double toward zero", () {
      expect(toIntOrNull(3.9), 3);
    });

    test("parses a numeric string", () {
      expect(toIntOrNull("42"), 42);
    });

    test("returns null for a decimal numeric string", () {
      expect(toIntOrNull("3.9"), isNull);
    });

    test("returns null for a non-numeric string", () {
      expect(toIntOrNull("x"), isNull);
    });

    test("returns null for null", () {
      expect(toIntOrNull(null), isNull);
    });
  });

  group("roundedIntOrNull", () {
    test("passes an int through unchanged", () {
      expect(roundedIntOrNull(7), 7);
    });

    test("rounds a double up at the halfway-or-above mark", () {
      expect(roundedIntOrNull(3.9), 4);
    });

    test("rounds a double down below the halfway mark", () {
      expect(roundedIntOrNull(3.4), 3);
    });

    test("parses a numeric string", () {
      expect(roundedIntOrNull("42"), 42);
    });

    test("returns null for a decimal numeric string", () {
      expect(roundedIntOrNull("3.9"), isNull);
    });

    test("returns null for a non-numeric string", () {
      expect(roundedIntOrNull("x"), isNull);
    });

    test("returns null for null", () {
      expect(roundedIntOrNull(null), isNull);
    });

    test("rounds where toIntOrNull truncates", () {
      // Key distinction: same input, different result.
      expect(toIntOrNull(3.9), 3);
      expect(roundedIntOrNull(3.9), 4);
    });
  });

  group("toStringKeyedMap", () {
    test("returns an equal map for a Map<String, dynamic>", () {
      final source = <String, dynamic>{"a": 1, "b": "two"};

      expect(toStringKeyedMap(source), source);
    });

    test("stringifies keys of a Map<dynamic, dynamic>", () {
      final source = <dynamic, dynamic>{1: "a"};

      expect(toStringKeyedMap(source), {"1": "a"});
    });

    test("returns null for a non-Map", () {
      expect(toStringKeyedMap(5), isNull);
    });

    test("returns null for null", () {
      expect(toStringKeyedMap(null), isNull);
    });
  });

  group("stringOrFallback", () {
    test("returns a non-empty string unchanged", () {
      expect(stringOrFallback("hi", fallback: "fb"), "hi");
    });

    test("returns the fallback for an empty string", () {
      expect(stringOrFallback("", fallback: "fb"), "fb");
    });

    test("returns the fallback for null", () {
      expect(stringOrFallback(null, fallback: "fb"), "fb");
    });

    test("returns the fallback for a non-string", () {
      expect(stringOrFallback(5, fallback: "fb"), "fb");
    });
  });

  group("boolOrFallback", () {
    test("returns true unchanged", () {
      expect(boolOrFallback(true), isTrue);
    });

    test("returns false unchanged", () {
      expect(boolOrFallback(false, fallback: true), isFalse);
    });

    test("returns the default fallback (false) for null", () {
      expect(boolOrFallback(null), isFalse);
    });

    test("returns an explicit fallback for null", () {
      expect(boolOrFallback(null, fallback: true), isTrue);
    });

    test("returns the fallback for a stringified bool", () {
      expect(boolOrFallback("true", fallback: false), isFalse);
    });
  });

  group("requiredString", () {
    test("trims surrounding whitespace", () {
      expect(requiredString("  hi ", "field"), "hi");
    });

    test("throws a FormatException naming the field for null", () {
      expect(
        () => requiredString(null, "courtName"),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            "message",
            contains("courtName"),
          ),
        ),
      );
    });

    test("throws a FormatException for an empty string", () {
      expect(
        () => requiredString("", "courtName"),
        throwsA(isA<FormatException>()),
      );
    });

    test("throws a FormatException for a whitespace-only string", () {
      expect(
        () => requiredString("   ", "courtName"),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group("optionalDateTime", () {
    test("passes a DateTime through unchanged", () {
      final value = DateTime.utc(2026, 6, 8, 10);

      expect(optionalDateTime(value), value);
    });

    test("parses an ISO-8601 string", () {
      expect(
        optionalDateTime("2026-06-08T10:00:00.000Z"),
        DateTime.utc(2026, 6, 8, 10),
      );
    });

    test("returns null for an unparseable string", () {
      expect(optionalDateTime("x"), isNull);
    });

    test("returns null for null", () {
      expect(optionalDateTime(null), isNull);
    });
  });

  group("requiredDateTime", () {
    test("parses a valid ISO-8601 string", () {
      expect(
        requiredDateTime("2026-06-08T10:00:00.000Z", "startTime"),
        DateTime.utc(2026, 6, 8, 10),
      );
    });

    test("throws a FormatException naming the field for null", () {
      expect(
        () => requiredDateTime(null, "startTime"),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            "message",
            contains("startTime"),
          ),
        ),
      );
    });

    test("throws a FormatException naming the field for an unparseable value",
        () {
      expect(
        () => requiredDateTime("not-a-date", "startTime"),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            "message",
            contains("startTime"),
          ),
        ),
      );
    });
  });
}
