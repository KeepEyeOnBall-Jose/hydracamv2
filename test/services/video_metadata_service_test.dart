import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/video_metadata_service.dart";

void main() {
  group("RecordedVideoMetadata.fromMap", () {
    test("returns null for a null map", () {
      expect(RecordedVideoMetadata.fromMap(null), isNull);
    });

    test("returns null when width is missing", () {
      expect(
        RecordedVideoMetadata.fromMap(const {"height": 1080}),
        isNull,
      );
    });

    test("returns null when height is missing", () {
      expect(
        RecordedVideoMetadata.fromMap(const {"width": 1920}),
        isNull,
      );
    });

    test("coerces int values for width and height", () {
      final metadata = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080, "durationMs": 5000},
      );

      expect(metadata, isNotNull);
      expect(metadata!.width, 1920);
      expect(metadata.height, 1080);
      expect(metadata.durationMs, 5000);
    });

    test("coerces non-int num values by truncating to int", () {
      final metadata = RecordedVideoMetadata.fromMap(
        const {"width": 1920.9, "height": 1080.4, "durationMs": 4999.7},
      );

      expect(metadata, isNotNull);
      expect(metadata!.width, 1920);
      expect(metadata.height, 1080);
      expect(metadata.durationMs, 4999);
    });

    test("coerces numeric string values for width, height, and duration", () {
      final metadata = RecordedVideoMetadata.fromMap(
        const {"width": "1280", "height": "720", "durationMs": "3000"},
      );

      expect(metadata, isNotNull);
      expect(metadata!.width, 1280);
      expect(metadata.height, 720);
      expect(metadata.durationMs, 3000);
    });

    test("returns null when width is a non-numeric string", () {
      expect(
        RecordedVideoMetadata.fromMap(
          const {"width": "wide", "height": 1080},
        ),
        isNull,
      );
    });

    test("coerces double and numeric-string frames per second", () {
      final fromDouble = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080, "framesPerSecond": 29.97},
      );
      final fromInt = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080, "framesPerSecond": 30},
      );
      final fromString = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080, "framesPerSecond": "59.94"},
      );

      expect(fromDouble!.framesPerSecond, 29.97);
      expect(fromInt!.framesPerSecond, 30.0);
      expect(fromString!.framesPerSecond, 59.94);
    });

    test("leaves frames per second null when absent or non-numeric", () {
      final missing = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080},
      );
      final invalid = RecordedVideoMetadata.fromMap(
        const {"width": 1920, "height": 1080, "framesPerSecond": "n/a"},
      );

      expect(missing!.framesPerSecond, isNull);
      expect(invalid!.framesPerSecond, isNull);
    });
  });

  group("RecordedVideoMetadata.framesPerSecondText", () {
    test("returns 'unknown' when frames per second is null", () {
      const metadata = RecordedVideoMetadata(width: 1920, height: 1080);

      expect(metadata.framesPerSecondText, "unknown");
    });

    test("returns 'unknown' when frames per second is zero or negative", () {
      const zero = RecordedVideoMetadata(
        width: 1920,
        height: 1080,
        framesPerSecond: 0,
      );
      const negative = RecordedVideoMetadata(
        width: 1920,
        height: 1080,
        framesPerSecond: -5,
      );

      expect(zero.framesPerSecondText, "unknown");
      expect(negative.framesPerSecondText, "unknown");
    });

    test("formats whole frame rates without decimals", () {
      const metadata = RecordedVideoMetadata(
        width: 1920,
        height: 1080,
        framesPerSecond: 30,
      );

      expect(metadata.framesPerSecondText, "30");
    });

    test("formats fractional frame rates with two decimals", () {
      const metadata = RecordedVideoMetadata(
        width: 1920,
        height: 1080,
        framesPerSecond: 29.97,
      );

      expect(metadata.framesPerSecondText, "29.97");
    });
  });
}
