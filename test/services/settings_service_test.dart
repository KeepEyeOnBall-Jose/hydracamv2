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
    expect(
      (await SharedPreferences.getInstance()).getString("videoCaptureProfile"),
      VideoCaptureProfile.dataSaver480p30.storageValue,
    );

    SharedPreferences.setMockInitialValues({"cameraQuality": "medium"});
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.compat720p30,
    );
    expect(
      (await SharedPreferences.getInstance()).getString("videoCaptureProfile"),
      VideoCaptureProfile.compat720p30.storageValue,
    );

    SharedPreferences.setMockInitialValues({"cameraQuality": "high"});
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.standard1080p30,
    );
    expect(
      (await SharedPreferences.getInstance()).getString("videoCaptureProfile"),
      VideoCaptureProfile.standard1080p30.storageValue,
    );

    SharedPreferences.setMockInitialValues({
      "cameraQuality": "low",
      "videoCaptureProfile": VideoCaptureProfile.sport1080p60.storageValue,
    });
    expect(
      await SettingsService.getVideoCaptureProfile(),
      VideoCaptureProfile.sport1080p60,
    );
    expect(
      (await SharedPreferences.getInstance()).getString("videoCaptureProfile"),
      VideoCaptureProfile.sport1080p60.storageValue,
    );
  });

  test("legacy camera quality API writes canonical video profile only",
      () async {
    SharedPreferences.setMockInitialValues({});

    await SettingsService.setCameraQuality("medium");

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString("videoCaptureProfile"),
      VideoCaptureProfile.compat720p30.storageValue,
    );
    expect(prefs.getString("cameraQuality"), isNull);
    expect(await SettingsService.getCameraQuality(), "medium");
  });

  test("canonical video profile setter clears stale legacy camera quality",
      () async {
    SharedPreferences.setMockInitialValues({"cameraQuality": "low"});

    await SettingsService.setVideoCaptureProfile(
      VideoCaptureProfile.sport1080p60,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString("cameraQuality"), isNull);
    expect(await SettingsService.getCameraQuality(), "high");
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

  test("auto-record defaults disabled and can be stored", () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsService.getAutoRecordMode(), isFalse);

    await SettingsService.setAutoRecordMode(true);

    expect(await SettingsService.getAutoRecordMode(), isTrue);
  });

  test("locale override can be stored and cleared", () async {
    SharedPreferences.setMockInitialValues({});

    expect(await SettingsService.getLocaleOverride(), isNull);

    await SettingsService.setLocaleOverride("pl");

    expect(await SettingsService.getLocaleOverride(), "pl");

    await SettingsService.clearLocaleOverride();

    expect(await SettingsService.getLocaleOverride(), isNull);
  });
}
