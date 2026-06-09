import "package:flutter/material.dart";

import "settings_service.dart";

class AppLocaleService extends ChangeNotifier {
  static final AppLocaleService instance = AppLocaleService();

  static const List<String> supportedLanguageCodes = [
    "en",
    "es",
    "de",
    "pl",
  ];

  String? _localeOverrideCode;

  String? get localeOverrideCode => _localeOverrideCode;

  Locale? get locale {
    final code = _localeOverrideCode;
    return code == null ? null : Locale(code);
  }

  Future<void> load() async {
    final storedCode = await SettingsService.getLocaleOverride();
    if (storedCode == null || storedCode.isEmpty) {
      _localeOverrideCode = null;
      return;
    }

    if (!supportedLanguageCodes.contains(storedCode)) {
      await SettingsService.clearLocaleOverride();
      _localeOverrideCode = null;
      return;
    }

    _localeOverrideCode = storedCode;
  }

  Future<void> setLocaleOverride(String? languageCode) async {
    if (languageCode != null &&
        !supportedLanguageCodes.contains(languageCode)) {
      throw ArgumentError.value(
        languageCode,
        "languageCode",
        "Unsupported locale override",
      );
    }

    if (languageCode == _localeOverrideCode) {
      return;
    }

    if (languageCode == null) {
      await SettingsService.clearLocaleOverride();
    } else {
      await SettingsService.setLocaleOverride(languageCode);
    }

    _localeOverrideCode = languageCode;
    notifyListeners();
  }
}
