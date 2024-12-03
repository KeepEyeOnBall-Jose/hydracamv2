import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../constants.dart';
import '../services/camera_service.dart';
import '../services/settings_service.dart';
import '../widgets/settings_option.dart'; // Import the widget

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _masterShouldRecord = true;
  String _cameraQuality = 'high';
  bool _deleteLocalAfterUpload = false;
  bool _autoUploadMaterials = true;
  bool _autoplayVideoOnMaster = false; // New setting

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Load settings from SharedPreferences.
  Future<void> _loadSettings() async {
    final shouldRecord = await SettingsService.getMasterShouldRecord();
    final cameraQuality = await SettingsService.getCameraQuality();
    final deleteLocalAfterUpload = await SettingsService.getDeleteLocalAfterUpload();
    final autoUploadMaterials = await SettingsService.getAutoUploadMaterials();
    final autoplayVideoOnMaster = await SettingsService.getAutoplayVideoOnMaster();

    setState(() {
      _masterShouldRecord = shouldRecord;
      _cameraQuality = cameraQuality;
      _deleteLocalAfterUpload = deleteLocalAfterUpload;
      _autoUploadMaterials = autoUploadMaterials;
      _autoplayVideoOnMaster = autoplayVideoOnMaster;
    });
  }

  // Update methods for each setting
  Future<void> _updateMasterRecording(bool value) async {
    await SettingsService.setMasterShouldRecord(value);
    setState(() {
      _masterShouldRecord = value;
    });
  }

  Future<void> _updateCameraQuality(String quality) async {
    await SettingsService.setCameraQuality(quality);
    setState(() {
      _cameraQuality = quality;
    });

    // Apply setting to camera
    final CameraQuality newQuality = _mapQualityStringToEnum(quality);
    await CameraService().setCameraQuality(newQuality);
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

  /// Map quality string to CameraQuality enum.
  CameraQuality _mapQualityStringToEnum(String quality) {
    switch (quality) {
      case 'high':
        return CameraQuality.high;
      case 'medium':
        return CameraQuality.medium;
      case 'low':
        return CameraQuality.low;
      default:
        throw Exception('Invalid quality string: $quality');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: SingleChildScrollView( // Allow scrolling if needed
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
                activeColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Camera Quality",
              control: DropdownButton<String>(
                value: _cameraQuality,
                items: const [
                  DropdownMenuItem(value: 'high', child: Text("High")),
                  DropdownMenuItem(value: 'medium', child: Text("Medium")),
                  DropdownMenuItem(value: 'low', child: Text("Low")),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updateCameraQuality(value);
                  }
                },
              ),
            ),
            SettingsOption(
              title: "Delete local after upload",
              control: Switch(
                value: _deleteLocalAfterUpload,
                onChanged: _updateDeleteLocalAfterUpload,
                activeColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            SettingsOption(
              title: "Auto-upload materials",
              control: Switch(
                value: _autoUploadMaterials,
                onChanged: _updateAutoUploadMaterials,
                activeColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
            // New setting with description
            SettingsOption(
              title: "Autoplay video on master",
              description:
              "Activate or deactivate automatic playback of videos after recording them on the master device.",
              control: Switch(
                value: _autoplayVideoOnMaster,
                onChanged: _updateAutoplayVideoOnMaster,
                activeColor: AppTheme.primaryColor,
                inactiveThumbColor: AppTheme.disabledButtonColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
