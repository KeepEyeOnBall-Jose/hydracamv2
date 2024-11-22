import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sport_cam_sync/screens/slave_screen.dart';
//import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import 'package:sport_cam_sync/services/device_id_provider.dart';
import 'package:sport_cam_sync/services/device_service.dart';
import 'package:sport_cam_sync/services/location_service.dart';
import 'package:sport_cam_sync/services/log_service.dart';
import 'package:sport_cam_sync/services/permission_service.dart';
import 'package:sport_cam_sync/app_theme.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure permissions are granted
  bool permissionsGranted = await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    LogService.instance.registerLog("Some permissions were not granted. The app may not work as expected.");
  }

  // Initialize the Device ID
  String deviceId = await DeviceIdService.getOrCreateDeviceId();
  LogService.instance.registerLog('Device ID: $deviceId');

  LogService.instance.registerLog("Initialize LocationService and try to get the location");
  // Initialize LocationService and try to get the location
  try {
    final locationService = LocationService();
    await locationService.initialize();
  } catch (e) {
    LogService.instance.registerLog("Failed to initialize location service: $e", function: "main()", file: "main.dart");
  }


  LogService.instance.registerLog("Prevent screen from turning off");
  // Prevent screen from turning off
  WakelockPlus.enable();

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
