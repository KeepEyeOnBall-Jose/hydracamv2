import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../screens/settings_screen.dart';
import '../screens/log_screen.dart';
import '../screens/uploader_info_screen.dart';
import '../services/alert_utils.dart';

class HydraCamAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;
  final List<Widget>? additionalActions; // For additional actions

  const HydraCamAppBar({
    Key? key,
    required this.title,
    required this.onBack,
    this.additionalActions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      actions: [
        if (additionalActions != null) ...additionalActions!,
        PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          onSelected: (value) {
            if (value == 'Device Info') {
              // Show info about device
              AlertUtils.showDeviceInfoDialog(context);
            } else if (value == 'Settings') {
              // Navigate to settings
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            } else if (value == 'Location Info') {
              // Show info about location
              AlertUtils.showLocationInfoDialog(context);
            } else if (value == 'Logs') {
              // Navigate to logs
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogScreen()),
              );
            } else if (value == 'Uploader Info') {
              // Navigate to uploader info screen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UploaderInfoScreen()),
              );
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'Device Info',
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: AppTheme.accentColor),
                  SizedBox(width: 8),
                  Text('Device Info'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'Settings',
              child: Row(
                children: const [
                  Icon(Icons.settings, color: AppTheme.accentColor),
                  SizedBox(width: 8),
                  Text('Settings'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'Location Info',
              child: Row(
                children: const [
                  Icon(Icons.location_on, color: AppTheme.accentColor),
                  SizedBox(width: 8),
                  Text('Location Info'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'Logs',
              child: Row(
                children: const [
                  Icon(Icons.list_alt, color: AppTheme.accentColor),
                  SizedBox(width: 8),
                  Text('Logs'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'Uploader Info',
              child: Row(
                children: const [
                  Icon(Icons.cloud_upload, color: AppTheme.accentColor),
                  SizedBox(width: 8),
                  Text('Uploader Info'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
