import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';

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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _masterShouldRecord = prefs.getBool('masterShouldRecord') ?? false;
    });
  }

  Future<void> _updateMasterRecording(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _masterShouldRecord = value;
    });
    await prefs.setBool('masterShouldRecord', value);
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
