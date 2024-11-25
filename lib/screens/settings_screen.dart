import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _masterShouldRecord = false;
  String _cameraQuality = 'high'; // Default quality

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final shouldRecord = await SettingsService.getMasterShouldRecord();
    final cameraQuality = await SettingsService.getCameraQuality();
    setState(() {
      _masterShouldRecord = shouldRecord;
      _cameraQuality = cameraQuality;
    });
  }

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
          ],
        ),
      ),
    );
  }
}
