import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/services/camera_setup_service.dart";
import "package:hydracam/services/device_level_service.dart";

void main() {
  final service = CameraSetupService.instance;

  tearDown(service.resetForTest);

  group("buildSetupStatusPayload", () {
    test("includes perspective and level readings when the sensor is available",
        () {
      service.setPerspective(
        CameraPerspectiveMetadata.fromId("center_backglass_parallel"),
      );
      service.updateLevelReading(
        DeviceLevelReading.fromAcceleration(
          x: 0,
          y: 0,
          z: 9.81,
          capturedAt: DateTime.utc(2026, 6, 8, 11, 30),
        ),
      );

      final payload = service.buildSetupStatusPayload();

      expect(payload["cameraPerspectiveId"], "center_backglass_parallel");
      expect(
        payload["cameraPerspectiveLabel"],
        "Centered behind back glass, parallel to front wall",
      );
      expect(payload["isLevel"], isTrue);
      expect(payload["sensorAvailable"], isTrue);
      expect(payload.containsKey("rollDegrees"), isTrue);
      expect(payload.containsKey("pitchDegrees"), isTrue);
      expect(payload["rollDegrees"], isA<double>());
      expect(payload["pitchDegrees"], isA<double>());
    });

    test("omits degree keys when the level reading is unavailable", () {
      service.setPerspective(
        CameraPerspectiveMetadata.fromId("tin_back_floor_center"),
      );
      service.updateLevelReading(
        DeviceLevelReading.unavailable(
          capturedAt: DateTime.utc(2026, 6, 8, 11, 30),
        ),
      );

      final payload = service.buildSetupStatusPayload();

      expect(payload["cameraPerspectiveId"], "tin_back_floor_center");
      expect(payload["sensorAvailable"], isFalse);
      expect(payload["isLevel"], isFalse);
      expect(payload.containsKey("rollDegrees"), isFalse);
      expect(payload.containsKey("pitchDegrees"), isFalse);
    });

    test("resets to the unknown perspective and unavailable level", () {
      service.setPerspective(
        CameraPerspectiveMetadata.fromId("right_backglass_diagonal"),
      );
      service.resetForTest();

      final payload = service.buildSetupStatusPayload();

      expect(payload["cameraPerspectiveId"], "unknown");
      expect(payload["sensorAvailable"], isFalse);
      expect(payload.containsKey("rollDegrees"), isFalse);
    });
  });
}
