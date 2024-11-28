import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../constants.dart';
import '../services/camera_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _masterShouldRecord = false;
  String _cameraQuality = 'high'; // Default quality
  bool _deleteLocalAfterUpload = false;
  bool _autoUploadMaterials = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final shouldRecord = await SettingsService.getMasterShouldRecord();
    final cameraQuality = await SettingsService.getCameraQuality();
    final deleteLocalAfterUpload = await SettingsService.getDeleteLocalAfterUpload();
    final autoUploadMaterials = await SettingsService.getAutoUploadMaterials(); // New

    setState(() {
      _masterShouldRecord = shouldRecord;
      _cameraQuality = cameraQuality;
      _deleteLocalAfterUpload = deleteLocalAfterUpload;
      _autoUploadMaterials = autoUploadMaterials;
    });
  }

  Future<void> _updateMasterRecording(bool value) async {
    await SettingsService.setMasterShouldRecord(value);
    setState(() {
      _masterShouldRecord = value;
    });
  }

  Future<void> _updateCameraQuality(String quality) async {
    // Store setting and update UI
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

  // Update the auto-upload setting
  Future<void> _updateAutoUploadMaterials(bool value) async {
    await SettingsService.setAutoUploadMaterials(value);
    setState(() {
      _autoUploadMaterials = value;
    });
  }


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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Preferences",
              style: AppTheme.headline1.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Master should record",
                  style: AppTheme.bodyText1,
                ),
                Switch(
                  value: _masterShouldRecord,
                  onChanged: _updateMasterRecording,
                  activeColor: AppTheme.primaryColor,
                  activeTrackColor: AppTheme.accentColor.withOpacity(0.5),
                  inactiveThumbColor: AppTheme.disabledButtonColor,
                  inactiveTrackColor: AppTheme.secondaryColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Camera Quality",
                  style: AppTheme.bodyText1,
                ),
                DropdownButton<String>(
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
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Delete local after upload",
                  style: AppTheme.bodyText1,
                ),
                Switch(
                  value: _deleteLocalAfterUpload,
                  onChanged: _updateDeleteLocalAfterUpload,
                  activeColor: AppTheme.primaryColor,
                  activeTrackColor: AppTheme.accentColor.withOpacity(0.5),
                  inactiveThumbColor: AppTheme.disabledButtonColor,
                  inactiveTrackColor: AppTheme.secondaryColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // New: Auto-upload materials setting
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Auto-upload materials",
                  style: AppTheme.bodyText1,
                ),
                Switch(
                  value: _autoUploadMaterials,
                  onChanged: _updateAutoUploadMaterials,
                  activeColor: AppTheme.primaryColor,
                  activeTrackColor: AppTheme.accentColor.withOpacity(0.5),
                  inactiveThumbColor: AppTheme.disabledButtonColor,
                  inactiveTrackColor: AppTheme.secondaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
