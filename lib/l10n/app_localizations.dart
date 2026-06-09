import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('pl')
  ];

  /// App shell menu item for device information.
  ///
  /// In en, this message translates to:
  /// **'Device Info'**
  String get appShellDeviceInfo;

  /// App shell menu item and Settings screen title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get appShellSettings;

  /// App shell menu item for camera selection.
  ///
  /// In en, this message translates to:
  /// **'Camera Selection'**
  String get appShellCameraSelection;

  /// App shell menu item for location information.
  ///
  /// In en, this message translates to:
  /// **'Location Info'**
  String get appShellLocationInfo;

  /// App shell menu item for application logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get appShellLogs;

  /// App shell menu item for uploader status.
  ///
  /// In en, this message translates to:
  /// **'Uploader Info'**
  String get appShellUploaderInfo;

  /// App shell menu item and dialog title for app version.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get appShellAppVersion;

  /// App shell menu item for user login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get appShellLogin;

  /// Dialog content showing the app version and build number.
  ///
  /// In en, this message translates to:
  /// **'Version: {version}\nBuild: {buildNumber}'**
  String appVersionDialogContent(String version, String buildNumber);

  /// Generic OK dialog action.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get dialogOk;

  /// Heading for general Settings preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesHeading;

  /// Settings row title for choosing the app language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// Settings row description for language override.
  ///
  /// In en, this message translates to:
  /// **'Choose an app language or use your device setting.'**
  String get settingsLanguageDescription;

  /// Dropdown option that clears the app language override.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystemDefault;

  /// Dropdown option for English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Dropdown option for Spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLanguageSpanish;

  /// Dropdown option for German.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settingsLanguageGerman;

  /// Dropdown option for Polish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get settingsLanguagePolish;

  /// Settings switch title controlling whether the master captures too.
  ///
  /// In en, this message translates to:
  /// **'Master should record'**
  String get settingsMasterShouldRecordTitle;

  /// Heading for camera capture settings.
  ///
  /// In en, this message translates to:
  /// **'Capture Settings'**
  String get settingsCaptureHeading;

  /// Settings row title for camera lens preference.
  ///
  /// In en, this message translates to:
  /// **'Camera Lens'**
  String get settingsCameraLensTitle;

  /// Settings row description for camera lens preference.
  ///
  /// In en, this message translates to:
  /// **'Squash: use Ultra Wide (0.5x) when the phone exposes it.'**
  String get settingsCameraLensDescription;

  /// Settings row title for video capture profile.
  ///
  /// In en, this message translates to:
  /// **'Video Profile'**
  String get settingsVideoProfileTitle;

  /// Settings row description for video capture profile.
  ///
  /// In en, this message translates to:
  /// **'Profiles are targets; the phone may fall back if unsupported.'**
  String get settingsVideoProfileDescription;

  /// Label showing the selected video target.
  ///
  /// In en, this message translates to:
  /// **'Target: {target}'**
  String settingsVideoTarget(String target);

  /// Settings switch title for deleting local media after upload.
  ///
  /// In en, this message translates to:
  /// **'Delete local after upload'**
  String get settingsDeleteLocalAfterUploadTitle;

  /// Settings switch title for automatic upload.
  ///
  /// In en, this message translates to:
  /// **'Auto-upload materials'**
  String get settingsAutoUploadMaterialsTitle;

  /// Settings row title for storage location.
  ///
  /// In en, this message translates to:
  /// **'Storage location'**
  String get settingsStorageLocationTitle;

  /// Settings row description for current storage location behavior.
  ///
  /// In en, this message translates to:
  /// **'HydraCam currently writes captures to the app session folder. Android SD-card selection needs a storage strategy before it can be enabled.'**
  String get settingsStorageLocationDescription;

  /// Settings storage location value.
  ///
  /// In en, this message translates to:
  /// **'Internal app storage'**
  String get settingsInternalAppStorage;

  /// Settings storage location secondary status.
  ///
  /// In en, this message translates to:
  /// **'SD card selection not configured'**
  String get settingsSdCardNotConfigured;

  /// Settings switch title for video autoplay on master.
  ///
  /// In en, this message translates to:
  /// **'Autoplay video on master'**
  String get settingsAutoplayVideoOnMasterTitle;

  /// Settings row description for video autoplay on master.
  ///
  /// In en, this message translates to:
  /// **'Activate or deactivate automatic playback of videos after recording them on the master device.'**
  String get settingsAutoplayVideoOnMasterDescription;

  /// Settings switch title for unattended automatic recording.
  ///
  /// In en, this message translates to:
  /// **'Auto-record mode'**
  String get settingsAutoRecordModeTitle;

  /// Settings row description for unattended automatic recording.
  ///
  /// In en, this message translates to:
  /// **'When enabled, unattended devices can start recording automatically after joining an active session.'**
  String get settingsAutoRecordModeDescription;

  /// Settings switch title for turning off slave screens while recording.
  ///
  /// In en, this message translates to:
  /// **'Screen Auto-Off'**
  String get settingsScreenAutoOffTitle;

  /// Settings row description for screen auto-off.
  ///
  /// In en, this message translates to:
  /// **'Turn off the slave screen during recording to save battery. The screen will reactivate automatically or when you wake it manually.'**
  String get settingsScreenAutoOffDescription;

  /// Settings row title for countdown timer duration.
  ///
  /// In en, this message translates to:
  /// **'Timer Duration'**
  String get settingsTimerDurationTitle;

  /// Settings row description for countdown timer duration.
  ///
  /// In en, this message translates to:
  /// **'Set the number of seconds for countdown timers when recording videos or taking photos.'**
  String get settingsTimerDurationDescription;

  /// Slider label showing the timer duration in seconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds'**
  String settingsTimerSeconds(int seconds);

  /// Text showing the currently selected timer duration.
  ///
  /// In en, this message translates to:
  /// **'Current timer duration: {seconds} seconds'**
  String settingsCurrentTimerDuration(int seconds);

  /// Settings switch title for flashing before and after recording.
  ///
  /// In en, this message translates to:
  /// **'Flash for Video Announcements'**
  String get settingsFlashForVideoAnnouncementsTitle;

  /// Settings row description for flashing before and after recording.
  ///
  /// In en, this message translates to:
  /// **'If enabled, the camera flash will blink before and after video recording to signal start/end.'**
  String get settingsFlashForVideoAnnouncementsDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
