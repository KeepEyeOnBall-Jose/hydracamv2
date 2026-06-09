// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appShellDeviceInfo => 'Device Info';

  @override
  String get appShellSettings => 'Settings';

  @override
  String get appShellCameraSelection => 'Camera Selection';

  @override
  String get appShellLocationInfo => 'Location Info';

  @override
  String get appShellLogs => 'Logs';

  @override
  String get appShellUploaderInfo => 'Uploader Info';

  @override
  String get appShellAppVersion => 'App Version';

  @override
  String get appShellLogin => 'Login';

  @override
  String appVersionDialogContent(String version, String buildNumber) {
    return 'Version: $version\nBuild: $buildNumber';
  }

  @override
  String get dialogOk => 'OK';

  @override
  String get settingsPreferencesHeading => 'Preferences';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageDescription =>
      'Choose an app language or use your device setting.';

  @override
  String get settingsLanguageSystemDefault => 'System default';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Spanish';

  @override
  String get settingsLanguageGerman => 'German';

  @override
  String get settingsLanguagePolish => 'Polish';

  @override
  String get settingsMasterShouldRecordTitle => 'Master should record';

  @override
  String get settingsCaptureHeading => 'Capture Settings';

  @override
  String get settingsCameraLensTitle => 'Camera Lens';

  @override
  String get settingsCameraLensDescription =>
      'Squash: use Ultra Wide (0.5x) when the phone exposes it.';

  @override
  String get settingsVideoProfileTitle => 'Video Profile';

  @override
  String get settingsVideoProfileDescription =>
      'Profiles are targets; the phone may fall back if unsupported.';

  @override
  String settingsVideoTarget(String target) {
    return 'Target: $target';
  }

  @override
  String get settingsDeleteLocalAfterUploadTitle => 'Delete local after upload';

  @override
  String get settingsAutoUploadMaterialsTitle => 'Auto-upload materials';

  @override
  String get settingsStorageLocationTitle => 'Storage location';

  @override
  String get settingsStorageLocationDescription =>
      'HydraCam currently writes captures to the app session folder. Android SD-card selection needs a storage strategy before it can be enabled.';

  @override
  String get settingsInternalAppStorage => 'Internal app storage';

  @override
  String get settingsSdCardNotConfigured => 'SD card selection not configured';

  @override
  String get settingsAutoplayVideoOnMasterTitle => 'Autoplay video on master';

  @override
  String get settingsAutoplayVideoOnMasterDescription =>
      'Activate or deactivate automatic playback of videos after recording them on the master device.';

  @override
  String get settingsAutoRecordModeTitle => 'Auto-record mode';

  @override
  String get settingsAutoRecordModeDescription =>
      'When enabled, unattended devices can start recording automatically after joining an active session.';

  @override
  String get settingsScreenAutoOffTitle => 'Screen Auto-Off';

  @override
  String get settingsScreenAutoOffDescription =>
      'Turn off the slave screen during recording to save battery. The screen will reactivate automatically or when you wake it manually.';

  @override
  String get settingsTimerDurationTitle => 'Timer Duration';

  @override
  String get settingsTimerDurationDescription =>
      'Set the number of seconds for countdown timers when recording videos or taking photos.';

  @override
  String settingsTimerSeconds(int seconds) {
    return '$seconds seconds';
  }

  @override
  String settingsCurrentTimerDuration(int seconds) {
    return 'Current timer duration: $seconds seconds';
  }

  @override
  String get settingsFlashForVideoAnnouncementsTitle =>
      'Flash for Video Announcements';

  @override
  String get settingsFlashForVideoAnnouncementsDescription =>
      'If enabled, the camera flash will blink before and after video recording to signal start/end.';
}
