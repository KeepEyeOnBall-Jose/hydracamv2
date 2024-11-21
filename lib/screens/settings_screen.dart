import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _masterShouldRecord = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final shouldRecord = await SettingsService.getMasterShouldRecord();
    setState(() {
      _masterShouldRecord = shouldRecord;
    });
  }

  Future<void> _updateMasterRecording(bool value) async {
    await SettingsService.setMasterShouldRecord(value);
    setState(() {
      _masterShouldRecord = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Settings"),
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
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
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
          ],
        ),
      ),
    );
  }
}
