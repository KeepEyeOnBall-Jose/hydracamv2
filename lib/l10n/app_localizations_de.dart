// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appShellDeviceInfo => 'Geräteinfo';

  @override
  String get appShellSettings => 'Einstellungen';

  @override
  String get appShellCameraSelection => 'Kameraauswahl';

  @override
  String get appShellLocationInfo => 'Standortinfo';

  @override
  String get appShellLogs => 'Protokolle';

  @override
  String get appShellUploaderInfo => 'Uploader-Info';

  @override
  String get appShellAppVersion => 'App-Version';

  @override
  String get appShellLogin => 'Anmelden';

  @override
  String appVersionDialogContent(String version, String buildNumber) {
    return 'Version: $version\nBuild: $buildNumber';
  }

  @override
  String get dialogOk => 'OK';

  @override
  String get settingsPreferencesHeading => 'Einstellungen';

  @override
  String get settingsLanguageTitle => 'Sprache';

  @override
  String get settingsLanguageDescription =>
      'Wähle eine App-Sprache oder nutze die Geräteeinstellung.';

  @override
  String get settingsLanguageSystemDefault => 'Systemstandard';

  @override
  String get settingsLanguageEnglish => 'Englisch';

  @override
  String get settingsLanguageSpanish => 'Spanisch';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get settingsLanguagePolish => 'Polnisch';

  @override
  String get settingsMasterShouldRecordTitle => 'Master soll aufnehmen';

  @override
  String get settingsCaptureHeading => 'Aufnahmeeinstellungen';

  @override
  String get settingsCameraLensTitle => 'Kameraobjektiv';

  @override
  String get settingsCameraLensDescription =>
      'Squash: Ultraweitwinkel (0,5x) verwenden, wenn das Telefon ihn anbietet.';

  @override
  String get settingsVideoProfileTitle => 'Videoprofil';

  @override
  String get settingsVideoProfileDescription =>
      'Profile sind Zielwerte; das Telefon kann ausweichen, wenn sie nicht unterstützt werden.';

  @override
  String settingsVideoTarget(String target) {
    return 'Ziel: $target';
  }

  @override
  String get settingsDeleteLocalAfterUploadTitle => 'Lokal nach Upload löschen';

  @override
  String get settingsAutoUploadMaterialsTitle =>
      'Materialien automatisch hochladen';

  @override
  String get settingsStorageLocationTitle => 'Speicherort';

  @override
  String get settingsStorageLocationDescription =>
      'HydraCam schreibt Aufnahmen derzeit in den App-Sitzungsordner. Die Android-SD-Kartenauswahl braucht eine Speicherstrategie, bevor sie aktiviert werden kann.';

  @override
  String get settingsInternalAppStorage => 'Interner App-Speicher';

  @override
  String get settingsSdCardNotConfigured =>
      'SD-Kartenauswahl nicht konfiguriert';

  @override
  String get settingsAutoplayVideoOnMasterTitle =>
      'Video auf Master automatisch abspielen';

  @override
  String get settingsAutoplayVideoOnMasterDescription =>
      'Automatische Wiedergabe von Videos nach der Aufnahme auf dem Master-Gerät aktivieren oder deaktivieren.';

  @override
  String get settingsAutoRecordModeTitle => 'Automatische Aufnahme';

  @override
  String get settingsAutoRecordModeDescription =>
      'Wenn aktiviert, können unbeaufsichtigte Geräte nach dem Beitritt zu einer aktiven Sitzung automatisch mit der Aufnahme beginnen.';

  @override
  String get settingsScreenAutoOffTitle => 'Bildschirm automatisch aus';

  @override
  String get settingsScreenAutoOffDescription =>
      'Schaltet den Slave-Bildschirm während der Aufnahme aus, um Akku zu sparen. Der Bildschirm wird automatisch oder beim manuellen Wecken wieder aktiv.';

  @override
  String get settingsTimerDurationTitle => 'Timerdauer';

  @override
  String get settingsTimerDurationDescription =>
      'Legt die Sekunden für Countdown-Timer beim Aufnehmen von Videos oder Fotos fest.';

  @override
  String settingsTimerSeconds(int seconds) {
    return '$seconds Sekunden';
  }

  @override
  String settingsCurrentTimerDuration(int seconds) {
    return 'Aktuelle Timerdauer: $seconds Sekunden';
  }

  @override
  String get settingsFlashForVideoAnnouncementsTitle =>
      'Blitz für Videoankündigungen';

  @override
  String get settingsFlashForVideoAnnouncementsDescription =>
      'Wenn aktiviert, blinkt der Kamerablitz vor und nach der Videoaufnahme, um Start/Ende zu signalisieren.';
}
