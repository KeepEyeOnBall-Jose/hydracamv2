import "package:flutter/material.dart";
import "../app_theme.dart";
import "../models/camera_capture_settings.dart";
import "../services/camera_service_singleton.dart";
import "../services/settings_service.dart";
import "../widgets/settings_option.dart"; // Import the widget

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
  int _timerDuration = 3;
  bool _screenAutoOff = false;
  bool _flashForVideoAnnounce = false;

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
    final timerDuration = await SettingsService.getTimerDuration();
    final screenAutoOff = await SettingsService.getScreenAutoOff();
    final flashForVideoAnnounce =
        await SettingsService.getFlashForVideoAnnounce();

    setState(() {
      _masterShouldRecord = shouldRecord;
      _lensPreference = lensPreference;
      _videoCaptureProfile = videoCaptureProfile;
      _deleteLocalAfterUpload = deleteLocalAfterUpload;
      _autoUploadMaterials = autoUploadMaterials;
      _autoplayVideoOnMaster = autoplayVideoOnMaster;
      _timerDuration = timerDuration;
      _screenAutoOff = screenAutoOff;
      _flashForVideoAnnounce = flashForVideoAnnounce;
    });
  }

  /// Update methods for each setting

  Future<void> _updateMasterRecording(bool value) async {
    await SettingsService.setMasterShouldRecord(value);
    setState(() {
      _masterShouldRecord = value;
    });
  }

  Future<void> _updateLensPreference(LensPreference preference) async {
    await SettingsService.setCameraLensPreference(preference);
    setState(() {
      _lensPreference = preference;
    });

    if (CameraServiceSingleton.isInitialized) {
      await CameraServiceSingleton.instance.setLensPreference(preference);
    }
  }

  Future<void> _updateVideoCaptureProfile(VideoCaptureProfile profile) async {
    await SettingsService.setVideoCaptureProfile(profile);
    setState(() {
      _videoCaptureProfile = profile;
    });

    if (CameraServiceSingleton.isInitialized) {
      await CameraServiceSingleton.instance.setVideoCaptureProfile(profile);
    }
  }

  Future<void> _updateDeleteLocalAfterUpload(bool value) async {
    await SettingsService.setDeleteLocalAfterUpload(value);
    setState(() {
      _deleteLocalAfterUpload = value;
    });
  }

  Future<void> _updateAutoUploadMaterials(bool value) async {
    await SettingsService.setAutoUploadMaterials(value);
    setState(() {
      _autoUploadMaterials = value;
    });
  }

  Future<void> _updateAutoplayVideoOnMaster(bool value) async {
    await SettingsService.setAutoplayVideoOnMaster(value);
    setState(() {
      _autoplayVideoOnMaster = value;
    });
  }

  Future<void> _updateTimerDuration(double value) async {
    final newDuration = value.toInt();
    await SettingsService.setTimerDuration(newDuration);
    setState(() {
      _timerDuration = newDuration;
    });
  }

  Future<void> _updateScreenAutoOff(bool value) async {
    await SettingsService.setScreenAutoOff(value);
    setState(() {
      _screenAutoOff = value;
    });
  }

  /// Widget with actual screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: SingleChildScrollView(
        // Allow scrolling if needed
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Preferences",
              style: AppTheme.headline1.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 20),
            SettingsOption(
              title: "Master should record",
              control: Switch(
                value: _masterShouldRecord,
                onChanged: _updateMasterRecording,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            Text(
              "Capture Settings",
              style: AppTheme.headline1.copyWith(fontSize: 20),
            ),
            SettingsOption(
              title: "Camera Lens",
              description:
                  "Squash: use Ultra Wide (0.5x) when the phone exposes it.",
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
              title: "Video Profile",
              description:
                  "Profiles are targets; the phone may fall back if unsupported.",
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
                "Target: ${_videoCaptureProfile.targetLabel}",
                style: AppTheme.bodyText1,
              ),
            ),
            SettingsOption(
              title: "Delete local after upload",
              control: Switch(
                value: _deleteLocalAfterUpload,
                onChanged: _updateDeleteLocalAfterUpload,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Auto-upload materials",
              control: Switch(
                value: _autoUploadMaterials,
                onChanged: _updateAutoUploadMaterials,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Autoplay video on master",
              description:
                  "Activate or deactivate automatic playback of videos after recording them on the master device.",
              control: Switch(
                value: _autoplayVideoOnMaster,
                onChanged: _updateAutoplayVideoOnMaster,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Screen Auto-Off",
              description:
                  "Turn off the slave screen during recording to save battery. The screen will reactivate automatically or when you wake it manually.",
              control: Switch(
                value: _screenAutoOff,
                onChanged: _updateScreenAutoOff,
                activeThumbColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Timer Duration",
              description:
                  "Set the number of seconds for countdown timers when recording videos or taking photos.",
              control: Column(
                children: [
                  Slider(
                    value: _timerDuration.toDouble(),
                    min: 0,
                    max: 6,
                    divisions: 6,
                    label: "$_timerDuration seconds",
                    onChanged: _updateTimerDuration,
                    thumbColor: AppTheme.primaryColor,
                    activeColor: AppTheme.lightAccentColor,
                    inactiveColor: AppTheme.disabledButtonColor,
                  ),
                  Text("Current timer duration: $_timerDuration seconds"),
                ],
              ),
            ),
            SettingsOption(
              title: "Flash for Video Announcements",
              description:
                  "If enabled, the camera flash will blink before and after video recording to signal start/end.",
              control: Switch(
                value: _flashForVideoAnnounce,
                onChanged: (value) async {
                  await SettingsService.setFlashForVideoAnnounce(value);
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
