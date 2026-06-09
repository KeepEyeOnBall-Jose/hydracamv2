import "package:camera/camera.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";

void main() {
  group("VideoCaptureProfile", () {
    test("maps sport 1080p60 to a 1080p target at 60 fps", () {
      const profile = VideoCaptureProfile.sport1080p60;

      expect(profile.resolutionPreset, ResolutionPreset.veryHigh);
      expect(profile.framesPerSecond, 60);
      expect(profile.label, "1080p at 60 fps");
      expect(profile.targetLabel, profile.label);
      expect(profile.description, contains("squash"));
    });

    test("maps 4K profiles to ultraHigh with expected frame rates", () {
      expect(
        VideoCaptureProfile.detail4k30.resolutionPreset,
        ResolutionPreset.ultraHigh,
      );
      expect(VideoCaptureProfile.detail4k30.framesPerSecond, 30);
      expect(
        VideoCaptureProfile.pro4k60.resolutionPreset,
        ResolutionPreset.ultraHigh,
      );
      expect(VideoCaptureProfile.pro4k60.framesPerSecond, 60);
    });
  });

  group("LensPreference", () {
    test("labels iPhone ultra-wide as 0.5x", () {
      const camera = CameraDescription(
        name: "com.apple.avfoundation.avcapturedevice.built-in_video:5",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.ultraWide,
      );

      expect(LensPreference.ultraWide.matches(camera), isTrue);
      expect(CameraLensLabels.describe(camera), "Ultra Wide (0.5x)");
    });

    test("labels Android back cameras by camera id when lens type is unknown",
        () {
      const camera = CameraDescription(
        name: "0",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );

      expect(CameraLensLabels.describe(camera), "Back camera 0");
    });
  });
}
