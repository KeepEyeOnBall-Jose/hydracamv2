import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";

void main() {
  group("CameraPerspectiveMetadata", () {
    test("exposes media-timeline canonical perspective options", () {
      final ids = CameraPerspectiveMetadata.canonicalPerspectives
          .map((perspective) => perspective.cameraPerspectiveId)
          .toList();

      expect(ids, contains("tin_back_floor_center"));
      expect(ids, contains("left_backglass_parallel"));
      expect(ids, contains("left_backglass_diagonal"));
      expect(ids, contains("right_backglass_parallel"));
      expect(ids, contains("right_backglass_diagonal"));
      expect(ids, contains("center_backglass_parallel"));
      expect(ids, contains("center_backglass_overhead_parallel"));
      expect(ids, contains("unknown"));
    });

    test("normalizes known ids to canonical labels", () {
      final perspective = CameraPerspectiveMetadata.fromId(
        "left_backglass_diagonal",
      );

      expect(perspective.cameraPerspectiveId, "left_backglass_diagonal");
      expect(
        perspective.cameraPerspectiveLabel,
        "Left corner, behind glass, diagonal to front-right",
      );
    });
  });

  group("MediaCaptureContext", () {
    test("serializes perspective, level, camera, profile, and device metadata",
        () {
      final capturedAt = DateTime.utc(2026, 6, 8, 11, 30);
      final context = MediaCaptureContext(
        perspective: CameraPerspectiveMetadata.fromId(
          "center_backglass_parallel",
        ),
        level: DeviceLevelMetadata(
          rollDegrees: 1.2,
          pitchDegrees: -3.4,
          toleranceDegrees: 5,
          isLevel: true,
          sensorAvailable: true,
          capturedAt: capturedAt,
        ),
        cameraName: "0",
        cameraLensDirection: "back",
        cameraSensorOrientation: 90,
        videoCaptureProfile: "sport1080p60",
        deviceId: "device-123",
      );

      final json = context.toJson();

      expect(json["cameraPerspectiveId"], "center_backglass_parallel");
      expect(
        json["cameraPerspectiveLabel"],
        "Centered behind back glass, parallel to front wall",
      );
      expect(json["cameraName"], "0");
      expect(json["cameraLensDirection"], "back");
      expect(json["cameraSensorOrientation"], 90);
      expect(json["videoCaptureProfile"], "sport1080p60");
      expect(json["deviceId"], "device-123");
      expect(json["deviceLevel"], isA<Map<String, dynamic>>());
      expect(json["deviceLevel"]["rollDegrees"], 1.2);
    });

    test("loads null and old metadata without capture context", () {
      expect(MediaCaptureContext.fromJson(null), isNull);
      expect(MediaCaptureContext.fromJson({}), isNull);
    });
  });
}
