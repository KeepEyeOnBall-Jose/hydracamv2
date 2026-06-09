// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appShellDeviceInfo => 'Informacje o urządzeniu';

  @override
  String get appShellSettings => 'Ustawienia';

  @override
  String get appShellCameraSelection => 'Wybór kamery';

  @override
  String get appShellLocationInfo => 'Informacje o lokalizacji';

  @override
  String get appShellLogs => 'Logi';

  @override
  String get appShellUploaderInfo => 'Informacje o wysyłaniu';

  @override
  String get appShellAppVersion => 'Wersja aplikacji';

  @override
  String get appShellLogin => 'Logowanie';

  @override
  String appVersionDialogContent(String version, String buildNumber) {
    return 'Wersja: $version\nBuild: $buildNumber';
  }

  @override
  String get dialogOk => 'OK';

  @override
  String get settingsPreferencesHeading => 'Preferencje';

  @override
  String get settingsLanguageTitle => 'Język';

  @override
  String get settingsLanguageDescription =>
      'Wybierz język aplikacji albo użyj ustawienia urządzenia.';

  @override
  String get settingsLanguageSystemDefault => 'Domyślny systemowy';

  @override
  String get settingsLanguageEnglish => 'Angielski';

  @override
  String get settingsLanguageSpanish => 'Hiszpański';

  @override
  String get settingsLanguageGerman => 'Niemiecki';

  @override
  String get settingsLanguagePolish => 'Polski';

  @override
  String get settingsMasterShouldRecordTitle => 'Master ma nagrywać';

  @override
  String get settingsCaptureHeading => 'Ustawienia przechwytywania';

  @override
  String get settingsCameraLensTitle => 'Obiektyw kamery';

  @override
  String get settingsCameraLensDescription =>
      'Squash: użyj ultraszerokiego kąta (0,5x), gdy telefon go udostępnia.';

  @override
  String get settingsVideoProfileTitle => 'Profil wideo';

  @override
  String get settingsVideoProfileDescription =>
      'Profile są celami; telefon może użyć opcji zapasowej, jeśli nie są obsługiwane.';

  @override
  String settingsVideoTarget(String target) {
    return 'Cel: $target';
  }

  @override
  String get settingsDeleteLocalAfterUploadTitle => 'Usuń lokalnie po wysłaniu';

  @override
  String get settingsAutoUploadMaterialsTitle =>
      'Automatycznie wysyłaj materiały';

  @override
  String get settingsStorageLocationTitle => 'Lokalizacja zapisu';

  @override
  String get settingsStorageLocationDescription =>
      'HydraCam zapisuje obecnie przechwycone media w folderze sesji aplikacji. Wybór karty SD na Androidzie wymaga strategii przechowywania przed włączeniem.';

  @override
  String get settingsInternalAppStorage => 'Wewnętrzna pamięć aplikacji';

  @override
  String get settingsSdCardNotConfigured => 'Wybór karty SD nieskonfigurowany';

  @override
  String get settingsAutoplayVideoOnMasterTitle =>
      'Automatycznie odtwarzaj wideo na masterze';

  @override
  String get settingsAutoplayVideoOnMasterDescription =>
      'Włącz lub wyłącz automatyczne odtwarzanie filmów po nagraniu ich na urządzeniu master.';

  @override
  String get settingsAutoRecordModeTitle => 'Automatyczne nagrywanie';

  @override
  String get settingsAutoRecordModeDescription =>
      'Po włączeniu urządzenia bez operatora mogą automatycznie rozpocząć nagrywanie po dołączeniu do aktywnej sesji.';

  @override
  String get settingsScreenAutoOffTitle => 'Automatyczne wyłączenie ekranu';

  @override
  String get settingsScreenAutoOffDescription =>
      'Wyłącza ekran slave podczas nagrywania, aby oszczędzać baterię. Ekran włączy się automatycznie albo po ręcznym wybudzeniu.';

  @override
  String get settingsTimerDurationTitle => 'Czas timera';

  @override
  String get settingsTimerDurationDescription =>
      'Ustaw liczbę sekund odliczania przy nagrywaniu filmów lub robieniu zdjęć.';

  @override
  String settingsTimerSeconds(int seconds) {
    return '$seconds sekund';
  }

  @override
  String settingsCurrentTimerDuration(int seconds) {
    return 'Aktualny czas timera: $seconds sekund';
  }

  @override
  String get settingsFlashForVideoAnnouncementsTitle =>
      'Flash dla sygnałów wideo';

  @override
  String get settingsFlashForVideoAnnouncementsDescription =>
      'Jeśli włączone, flash kamery mignie przed i po nagrywaniu wideo, aby zasygnalizować start/koniec.';
}
