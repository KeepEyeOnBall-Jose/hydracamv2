import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sport_cam_sync/screens/slave_screen.dart';
//import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import 'package:sport_cam_sync/services/device_id_provider.dart';
import 'package:sport_cam_sync/services/device_service.dart';
import 'package:sport_cam_sync/services/permission_service.dart';
import 'package:sport_cam_sync/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure permissions are granted
  bool permissionsGranted = await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    if (kDebugMode) {
      print("Some permissions were not granted. The app may not work as expected.");
    }
  }

  // Initialize the Device ID
  String deviceId = await DeviceIdService.getOrCreateDeviceId();
  if (kDebugMode) {
    print('Device ID: $deviceId');
  } // Debug

  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceIdProvider(deviceId),
      child: const HydraCamApp(),
    ),
  );
}

class HydraCamApp extends StatelessWidget {
  const HydraCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HydraCam',
      theme: AppTheme.lightTheme,
      home: const SlaveScreen(isAutoMode: true), // Start in SlaveScreen with auto mode
    );
  }
}
