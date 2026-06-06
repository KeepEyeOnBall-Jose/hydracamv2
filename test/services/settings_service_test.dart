import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
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
}
