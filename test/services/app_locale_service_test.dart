import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/app_locale_service.dart";
import "package:hydracam/services/settings_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  tearDown(() {
    SettingsService.clearTestOverrides();
  });

  test("loads a stored locale override", () async {
    SharedPreferences.setMockInitialValues({"localeOverride": "pl"});
    final service = AppLocaleService();

    await service.load();

    expect(service.localeOverrideCode, "pl");
    expect(service.locale, const Locale("pl"));
  });

  test("clears unsupported stored locale overrides", () async {
    SharedPreferences.setMockInitialValues({"localeOverride": "fr"});
    final service = AppLocaleService();

    await service.load();

    expect(service.localeOverrideCode, isNull);
    expect(service.locale, isNull);
    expect(await SettingsService.getLocaleOverride(), isNull);
  });

  test("notifies listeners when locale override changes", () async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLocaleService();
    var notificationCount = 0;
    service.addListener(() {
      notificationCount++;
    });

    await service.load();
    await service.setLocaleOverride("de");

    expect(service.localeOverrideCode, "de");
    expect(service.locale, const Locale("de"));
    expect(notificationCount, 1);
    expect(await SettingsService.getLocaleOverride(), "de");
  });
}
