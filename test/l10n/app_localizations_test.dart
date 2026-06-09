import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/l10n/app_localizations.dart";

void main() {
  test("seeded translations use locale-native spelling", () async {
    final es = await AppLocalizations.delegate.load(const Locale("es"));
    final de = await AppLocalizations.delegate.load(const Locale("de"));
    final pl = await AppLocalizations.delegate.load(const Locale("pl"));

    expect(es.settingsAutoRecordModeTitle, "Grabación automática");
    expect(es.settingsLanguageEnglish, "Inglés");
    expect(es.settingsLanguageSpanish, "Español");

    expect(de.settingsAutoRecordModeTitle, "Automatische Aufnahme");
    expect(de.appShellDeviceInfo, "Geräteinfo");
    expect(de.settingsLanguageDescription, contains("Geräteeinstellung"));

    expect(pl.settingsAutoRecordModeTitle, "Automatyczne nagrywanie");
    expect(pl.settingsLanguageTitle, "Język");
    expect(pl.settingsLanguageDescription, contains("urządzenia"));
  });
}
