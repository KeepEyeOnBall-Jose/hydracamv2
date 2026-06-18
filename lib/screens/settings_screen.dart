import "package:flutter/material.dart";
import "../app_theme.dart";
import "../l10n/app_localizations.dart";
import "../models/camera_capture_settings.dart";
import "../services/app_locale_service.dart";
import "../services/camera_service_singleton.dart";
import "../services/settings_service.dart";
import "../widgets/hydracam_surface.dart";
import "../widgets/settings_option.dart"; // Import the widget

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    AppLocaleService? localeService,
  }) : _localeService = localeService;

  final AppLocaleService? _localeService;

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  /// List of available settings

  bool _masterShouldRecord = true;
  LensPreference _lensPreference = LensPreference.autoBack;
  VideoCaptureProfile _videoCaptureProfile =
      VideoCaptureProfile.standard1080p30;
  bool _deleteLocalAfterUpload = false;
  bool _autoUploadMaterials = true;
  bool _autoplayVideoOnMaster = false;
  bool _autoRecordMode = false;
  int _timerDuration = 3;
  bool _screenAutoOff = false;
  bool _flashForVideoAnnounce = false;
  String _selectedLocaleCode = _systemLocaleCode;

  static const String _systemLocaleCode = "system";

  AppLocaleService get _localeService =>
      widget._localeService ?? AppLocaleService.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load settings from SharedPreferences.
  Future<void> _loadSettings() async {
    final shouldRecord = await SettingsService.getMasterShouldRecord();
    final lensPreference = await SettingsService.getCameraLensPreference();
    final videoCaptureProfile = await SettingsService.getVideoCaptureProfile();
    final deleteLocalAfterUpload =
        await SettingsService.getDeleteLocalAfterUpload();
    final autoUploadMaterials = await SettingsService.getAutoUploadMaterials();
    final autoplayVideoOnMaster =
        await SettingsService.getAutoplayVideoOnMaster();
    final autoRecordMode = await SettingsService.getAutoRecordMode();
    final timerDuration = await SettingsService.getTimerDuration();
    final screenAutoOff = await SettingsService.getScreenAutoOff();
    final flashForVideoAnnounce =
        await SettingsService.getFlashForVideoAnnounce();
    await _localeService.load();
    if (!mounted) return;
    final localeCode = _localeService.localeOverrideCode ?? _systemLocaleCode;

    setState(() {
      _masterShouldRecord = shouldRecord;
      _lensPreference = lensPreference;
      _videoCaptureProfile = videoCaptureProfile;
      _deleteLocalAfterUpload = deleteLocalAfterUpload;
      _autoUploadMaterials = autoUploadMaterials;
      _autoplayVideoOnMaster = autoplayVideoOnMaster;
      _autoRecordMode = autoRecordMode;
      _timerDuration = timerDuration;
      _screenAutoOff = screenAutoOff;
      _flashForVideoAnnounce = flashForVideoAnnounce;
      _selectedLocaleCode = localeCode;
    });
  }

  /// Update methods for each setting

  Future<void> _updateMasterRecording(bool value) async {
    await SettingsService.setMasterShouldRecord(value);
    if (!mounted) return;
    setState(() {
      _masterShouldRecord = value;
    });
  }

  Future<void> _updateLensPreference(LensPreference preference) async {
    await SettingsService.setCameraLensPreference(preference);
    if (!mounted) return;
    setState(() {
      _lensPreference = preference;
    });

    if (CameraServiceSingleton.isInitialized) {
      await CameraServiceSingleton.instance.setLensPreference(preference);
    }
  }

  Future<void> _updateVideoCaptureProfile(VideoCaptureProfile profile) async {
    await SettingsService.setVideoCaptureProfile(profile);
    if (!mounted) return;
    setState(() {
      _videoCaptureProfile = profile;
    });

    if (CameraServiceSingleton.isInitialized) {
      await CameraServiceSingleton.instance.setVideoCaptureProfile(profile);
    }
  }

  Future<void> _updateDeleteLocalAfterUpload(bool value) async {
    await SettingsService.setDeleteLocalAfterUpload(value);
    if (!mounted) return;
    setState(() {
      _deleteLocalAfterUpload = value;
    });
  }

  Future<void> _updateAutoUploadMaterials(bool value) async {
    await SettingsService.setAutoUploadMaterials(value);
    if (!mounted) return;
    setState(() {
      _autoUploadMaterials = value;
    });
  }

  Future<void> _updateAutoplayVideoOnMaster(bool value) async {
    await SettingsService.setAutoplayVideoOnMaster(value);
    if (!mounted) return;
    setState(() {
      _autoplayVideoOnMaster = value;
    });
  }

  Future<void> _updateAutoRecordMode(bool value) async {
    await SettingsService.setAutoRecordMode(value);
    if (!mounted) return;
    setState(() {
      _autoRecordMode = value;
    });
  }

  Future<void> _updateTimerDuration(double value) async {
    final newDuration = value.toInt();
    await SettingsService.setTimerDuration(newDuration);
    if (!mounted) return;
    setState(() {
      _timerDuration = newDuration;
    });
  }

  Future<void> _updateScreenAutoOff(bool value) async {
    await SettingsService.setScreenAutoOff(value);
    if (!mounted) return;
    setState(() {
      _screenAutoOff = value;
    });
  }

  Future<void> _updateLocaleOverride(String value) async {
    final overrideCode = value == _systemLocaleCode ? null : value;
    await _localeService.setLocaleOverride(overrideCode);
    if (!mounted) return;
    setState(() {
      _selectedLocaleCode = value;
    });
  }

  List<DropdownMenuItem<String>> _localeOverrideItems(AppLocalizations l10n) {
    return [
      DropdownMenuItem(
        value: _systemLocaleCode,
        child: Text(l10n.settingsLanguageSystemDefault),
      ),
      DropdownMenuItem(
        value: "en",
        child: Text(l10n.settingsLanguageEnglish),
      ),
      DropdownMenuItem(
        value: "es",
        child: Text(l10n.settingsLanguageSpanish),
      ),
      DropdownMenuItem(
        value: "de",
        child: Text(l10n.settingsLanguageGerman),
      ),
      DropdownMenuItem(
        value: "pl",
        child: Text(l10n.settingsLanguagePolish),
      ),
    ];
  }

  /// Widget with actual screen
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appShellSettings),
      ),
      body: SingleChildScrollView(
        // Allow scrolling if needed
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HydraCamToolbar(
              children: [
                const Icon(Icons.tune_outlined, color: AppTheme.accent),
                Text(
                  l10n.settingsPreferencesHeading,
                  style: AppTheme.headline1.copyWith(fontSize: 24),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsOption(
              title: l10n.settingsLanguageTitle,
              description: l10n.settingsLanguageDescription,
              control: DropdownButton<String>(
                key: const ValueKey("localeOverrideDropdown"),
                value: _selectedLocaleCode,
                items: _localeOverrideItems(l10n),
                onChanged: (value) {
                  if (value != null) {
                    _updateLocaleOverride(value);
                  }
                },
              ),
            ),
            SettingsOption(
              title: l10n.settingsMasterShouldRecordTitle,
              control: Switch(
                value: _masterShouldRecord,
                onChanged: _updateMasterRecording,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: HydraCamBadge(
                label: l10n.settingsCaptureHeading,
                icon: Icons.videocam_outlined,
                tone: HydraCamStatusTone.active,
              ),
            ),
            SettingsOption(
              title: l10n.settingsCameraLensTitle,
              description: l10n.settingsCameraLensDescription,
              control: DropdownButton<LensPreference>(
                value: _lensPreference,
                items: LensPreference.values
                    .map(
                      (preference) => DropdownMenuItem(
                        value: preference,
                        child: Text(preference.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    _updateLensPreference(value);
                  }
                },
              ),
            ),
            SettingsOption(
              title: l10n.settingsVideoProfileTitle,
              description: l10n.settingsVideoProfileDescription,
              control: DropdownButton<VideoCaptureProfile>(
                value: _videoCaptureProfile,
                items: VideoCaptureProfile.values
                    .map(
                      (profile) => DropdownMenuItem(
                        value: profile,
                        child: Text(profile.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    _updateVideoCaptureProfile(value);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                l10n.settingsVideoTarget(_videoCaptureProfile.targetLabel),
                style: AppTheme.bodyText1,
              ),
            ),
            SettingsOption(
              title: l10n.settingsDeleteLocalAfterUploadTitle,
              control: Switch(
                value: _deleteLocalAfterUpload,
                onChanged: _updateDeleteLocalAfterUpload,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: l10n.settingsAutoUploadMaterialsTitle,
              control: Switch(
                value: _autoUploadMaterials,
                onChanged: _updateAutoUploadMaterials,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: l10n.settingsStorageLocationTitle,
              description: l10n.settingsStorageLocationDescription,
              control: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.settingsInternalAppStorage,
                    style: AppTheme.bodyText1,
                    textAlign: TextAlign.right,
                  ),
                  Text(
                    l10n.settingsSdCardNotConfigured,
                    style: AppTheme.bodyText1.copyWith(
                      color: AppTheme.disabledButtonColor,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            SettingsOption(
              title: l10n.settingsAutoplayVideoOnMasterTitle,
              description: l10n.settingsAutoplayVideoOnMasterDescription,
              control: Switch(
                value: _autoplayVideoOnMaster,
                onChanged: _updateAutoplayVideoOnMaster,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: l10n.settingsAutoRecordModeTitle,
              description: l10n.settingsAutoRecordModeDescription,
              control: Switch(
                key: const ValueKey("autoRecordMode"),
                value: _autoRecordMode,
                onChanged: _updateAutoRecordMode,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: l10n.settingsScreenAutoOffTitle,
              description: l10n.settingsScreenAutoOffDescription,
              control: Switch(
                value: _screenAutoOff,
                onChanged: _updateScreenAutoOff,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: l10n.settingsTimerDurationTitle,
              description: l10n.settingsTimerDurationDescription,
              control: Column(
                children: [
                  Slider(
                    value: _timerDuration.toDouble(),
                    min: 0,
                    max: 6,
                    divisions: 6,
                    label: l10n.settingsTimerSeconds(_timerDuration),
                    onChanged: _updateTimerDuration,
                    thumbColor: AppTheme.primaryColor,
                    activeColor: AppTheme.lightAccentColor,
                    inactiveColor: AppTheme.disabledButtonColor,
                  ),
                  Text(l10n.settingsCurrentTimerDuration(_timerDuration)),
                ],
              ),
            ),
            SettingsOption(
              title: l10n.settingsFlashForVideoAnnouncementsTitle,
              description: l10n.settingsFlashForVideoAnnouncementsDescription,
              control: Switch(
                value: _flashForVideoAnnounce,
                onChanged: (value) async {
                  await SettingsService.setFlashForVideoAnnounce(value);
                  if (!mounted) return;
                  setState(() {
                    _flashForVideoAnnounce = value;
                  });
                },
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
