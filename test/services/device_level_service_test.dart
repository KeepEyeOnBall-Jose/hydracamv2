import "dart:math" as math;

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/device_level_service.dart";

void main() {
  group("DeviceLevelReading", () {
    test("reports green level when roll is within two degrees", () {
      final reading = DeviceLevelReading.fromAcceleration(
        x: 0,
        y: 0,
        z: 9.81,
        capturedAt: DateTime.utc(2026, 6, 8),
      );

      expect(reading.rollDegrees, closeTo(0, 0.01));
      expect(reading.pitchDegrees, closeTo(0, 0.01));
      expect(reading.zone, DeviceLevelZone.green);
      expect(reading.isLevel, isTrue);
    });

    test("reports amber warning when roll is within five degrees", () {
      final radians = 3 * math.pi / 180;
      final reading = DeviceLevelReading.fromAcceleration(
        x: math.sin(radians) * 9.81,
        y: 0,
        z: math.cos(radians) * 9.81,
        capturedAt: DateTime.utc(2026, 6, 8),
      );

      expect(reading.rollDegrees, closeTo(3, 0.05));
      expect(reading.zone, DeviceLevelZone.amber);
      expect(reading.isLevel, isTrue);
    });

    test("reports red warning when roll is outside tolerance", () {
      final radians = 8 * math.pi / 180;
      final reading = DeviceLevelReading.fromAcceleration(
        x: math.sin(radians) * 9.81,
        y: 0,
        z: math.cos(radians) * 9.81,
        capturedAt: DateTime.utc(2026, 6, 8),
      );

      expect(reading.rollDegrees, closeTo(8, 0.05));
      expect(reading.zone, DeviceLevelZone.red);
      expect(reading.isLevel, isFalse);
    });

    test("records sensor unavailable without blocking capture", () {
      final reading = DeviceLevelReading.unavailable(
        capturedAt: DateTime.utc(2026, 6, 8),
      );

      expect(reading.sensorAvailable, isFalse);
      expect(reading.rollDegrees, isNull);
      expect(reading.pitchDegrees, isNull);
      expect(reading.zone, DeviceLevelZone.unavailable);
      expect(reading.isLevel, isFalse);
    });
  });
}
