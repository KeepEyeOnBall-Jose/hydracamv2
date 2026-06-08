import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";
import "package:hydracam/services/settings_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SettingsService.clearTestOverrides();
  });

  test("master recording defaults off on macOS controller builds", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});

    final shouldRecord = await SettingsService.getMasterShouldRecord();

    expect(shouldRecord, isFalse);
  });

  test("stored master recording preference overrides macOS default", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({"masterShouldRecord": true});

    final shouldRecord = await SettingsService.getMasterShouldRecord();

    expect(shouldRecord, isTrue);
  });

  test("new installs default to auto back lens and standard 1080p30", () async {
    SharedPreferences.setMockInitialValues({});

    final lensPreference = await SettingsService.getCameraLensPreference();
    final videoProfile = await SettingsService.getVideoCaptureProfile();

    expect(lensPreference, LensPreference.autoBack);
    expect(videoProfile, VideoCaptureProfile.standard1080p30);
  });

  test("legacy camera quality migrates to video capture profiles", () async {
    SharedPreferences.setMockInitialValues({"cameraQuality": "low"});
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.dataSaver480p30,
    );

    SharedPreferences.setMockInitialValues({"cameraQuality": "medium"});
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.compat720p30,
    );

    SharedPreferences.setMockInitialValues({"cameraQuality": "high"});
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.standard1080p30,
    );
  });

  test("stores selected camera name independently from lens preference",
      () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsService.setCameraLensPreference(LensPreference.ultraWide);
    await SettingsService.setSelectedCameraName("iphone-ultra-wide");

    expect(
      await SettingsService.getCameraLensPreference(),
      LensPreference.ultraWide,
    );
    expect(await SettingsService.getSelectedCameraName(), "iphone-ultra-wide");
  });

  test("stores selected camera perspective by canonical id", () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      (await SettingsService.getCameraPerspective()).cameraPerspectiveId,
      "unknown",
    );

    await SettingsService.setCameraPerspectiveId("right_backglass_diagonal");

    final perspective = await SettingsService.getCameraPerspective();
    expect(perspective.cameraPerspectiveId, "right_backglass_diagonal");
    expect(
      perspective.cameraPerspectiveLabel,
      "Right corner, behind glass, diagonal to front-left",
    );
  });
}
