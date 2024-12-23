import 'package:flutter/material.dart';
import 'package:hydracam/services/battery_service.dart';
import 'package:hydracam/services/camera_service.dart';
import 'package:hydracam/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:hydracam/screens/slave_screen.dart';
//import 'package:sport_cam_sync/screens/role_selection_screen.dart';
import 'package:hydracam/services/device_id_provider.dart';
import 'package:hydracam/services/device_service.dart';
import 'package:hydracam/services/location_service.dart';
import 'package:hydracam/services/log_service.dart';
import 'package:hydracam/services/permission_service.dart';
import 'package:hydracam/app_theme.dart';
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

  // GlobalKey para ScaffoldMessenger
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  // Init BatteryService
  BatteryService.initialize(
    scaffoldMessengerKey: scaffoldMessengerKey,
  );

  // Init StorageService
  StorageService.initialize(
    scaffoldMessengerKey: scaffoldMessengerKey,
    lowStorageThreshold: 1.5, // Optional custom threshold in GB
    onCriticalStorageCallback: () {
      // TODO: Define la lógica para manejar almacenamiento crítico
      // Por ejemplo, detén la grabación si está activa
      LogService.instance.registerLog("Critical storage: triggering recording stop.");
      CameraService().stopRecordingVideo(); // TODO: Maybe something different
    },
  );



  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceIdProvider(deviceId),
      child: HydraCamApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
      ),
    ),
  );
}

class HydraCamApp extends StatelessWidget {

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  const HydraCamApp({super.key, required this.scaffoldMessengerKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HydraCam',
      theme: AppTheme.lightTheme,
      scaffoldMessengerKey: scaffoldMessengerKey, // For global snackbars
      home: const SlaveScreen(isAutoMode: true), // Start in SlaveScreen with auto mode
    );
  }
}
