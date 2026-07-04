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

    test("derives targetLabel for the non-default profiles", () {
      expect(VideoCaptureProfile.dataSaver480p30.targetLabel, "480p at 30 fps");
      expect(VideoCaptureProfile.compat720p30.targetLabel, "720p at 30 fps");
      expect(
        VideoCaptureProfile.standard1080p30.targetLabel,
        "1080p at 30 fps",
      );
      expect(VideoCaptureProfile.detail4k30.targetLabel, "4K at 30 fps");
      expect(VideoCaptureProfile.pro4k60.targetLabel, "4K at 60 fps");
    });

    test("resolves a known storage value", () {
      expect(
        VideoCaptureProfile.fromStorageValue("sport1080p60"),
        VideoCaptureProfile.sport1080p60,
      );
    });

    test("falls back to the default profile for an invalid storage value", () {
      expect(
        VideoCaptureProfile.fromStorageValue("nope"),
        VideoCaptureProfile.standard1080p30,
      );
      expect(
        VideoCaptureProfile.fromStorageValue(null),
        VideoCaptureProfile.standard1080p30,
      );
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

    test("resolves known storage values and defaults to autoBack", () {
      expect(LensPreference.fromStorageValue("wide"), LensPreference.wide);
      expect(
        LensPreference.fromStorageValue("telephoto"),
        LensPreference.telephoto,
      );
      expect(LensPreference.fromStorageValue("front"), LensPreference.front);
      expect(
        LensPreference.fromStorageValue("unknown-value"),
        LensPreference.autoBack,
      );
      expect(LensPreference.fromStorageValue(null), LensPreference.autoBack);
    });

    test("matches wide against an explicit wide lens", () {
      const camera = CameraDescription(
        name: "wide",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.wide,
      );

      expect(LensPreference.wide.matches(camera), isTrue);
      expect(LensPreference.telephoto.matches(camera), isFalse);
    });

    test("matches wide against an unknown-type back lens", () {
      const camera = CameraDescription(
        name: "0",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      );

      expect(LensPreference.wide.matches(camera), isTrue);
    });

    test("matches telephoto against a telephoto lens", () {
      const camera = CameraDescription(
        name: "tele",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.telephoto,
      );

      expect(LensPreference.telephoto.matches(camera), isTrue);
      expect(LensPreference.front.matches(camera), isFalse);
    });

    test("matches front against a front-facing lens", () {
      const camera = CameraDescription(
        name: "1",
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      expect(LensPreference.front.matches(camera), isTrue);
      expect(LensPreference.autoBack.matches(camera), isFalse);
    });

    test("matches autoBack against any back-facing lens", () {
      const camera = CameraDescription(
        name: "0",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.telephoto,
      );

      expect(LensPreference.autoBack.matches(camera), isTrue);
    });

    test("describes wide, telephoto, and an unknown front lens", () {
      const wideCamera = CameraDescription(
        name: "wide",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.wide,
      );
      const telephotoCamera = CameraDescription(
        name: "tele",
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
        lensType: CameraLensType.telephoto,
      );
      const frontCamera = CameraDescription(
        name: "1",
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 270,
      );

      expect(CameraLensLabels.describe(wideCamera), "Wide (1x)");
      expect(CameraLensLabels.describe(telephotoCamera), "Telephoto");
      expect(CameraLensLabels.describe(frontCamera), "Front camera 1");
    });
  });
}
