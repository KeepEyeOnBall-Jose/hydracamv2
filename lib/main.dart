import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import 'package:sport_cam_sync/services/device_id_provider.dart';
import 'package:sport_cam_sync/services/device_service.dart';
import 'package:sport_cam_sync/services/permission_service.dart'; // Import the permission service
import 'package:sport_cam_sync/app_theme.dart'; // Import the theme

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure permissions are granted
  bool permissionsGranted = await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    // Log or handle the case where permissions are not granted
    print("Some permissions were not granted. The app may not work as expected.");
  }

  // Initialize the Device ID
  String deviceId = await DeviceIdService.getOrCreateDeviceId();
  print('Device ID: $deviceId'); // Debug

  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceIdProvider(deviceId),
      child: HydraCamApp(),
    ),
  );
}

/// Main entry point of the application.
class HydraCamApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HydraCam',
      theme: AppTheme.lightTheme, // Apply the custom theme
      home: RoleSelectionScreen(), // Set initial screen to role selection
    );
  }
}
