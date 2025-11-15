import "package:flutter/material.dart";
import "services/battery_service.dart";
import "services/camera_service.dart";
import "services/camera_service_singleton.dart";
import "services/storage_service.dart";
import "package:provider/provider.dart";
import "slave/slave_screen.dart";
import "services/device_id_provider.dart";
import "services/device_service.dart";
import "services/location_service.dart";
import "services/log_service.dart";
import "services/permission_service.dart";
import "app_theme.dart";
import "package:wakelock_plus/wakelock_plus.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bool permissionsGranted = await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    LogService.instance.registerLog("Some permissions were not granted. The app may not work as expected.");
  }

  final String deviceId = await DeviceIdService.getOrCreateDeviceId();
  LogService.instance.registerLog("Device ID: $deviceId");

  LogService.instance.registerLog("Initialize LocationService and try to get the location");
  try {
    final locationService = LocationService();
    await locationService.initialize();
  } catch (e) {
    LogService.instance.registerLog("Failed to initialize location service: $e", function: "main()", file: "main.dart");
  }

  LogService.instance.registerLog("Prevent screen from turning off");
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
    return MultiProvider(
      providers: [
        Provider<StorageService>(
          create: (context) => StorageService(
            messengerState: ScaffoldMessenger.of(context),
            lowStorageThreshold: 1.5,
            criticalStorageThreshold: 0.5,
            onCriticalStorageCallback: () {
              LogService.instance.registerLog("Critical storage: triggering recording stop.");
              CameraServiceSingleton.instance.forceStopRecordingDueToStorage();
            },
          ),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<BatteryService>(
          create: (context) => BatteryService(
            messengerState: ScaffoldMessenger.of(context),
          ),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<CameraService>(
          create: (context) => CameraServiceSingleton.initialize(
            Provider.of<StorageService>(context, listen: false),
          ),
        ),
      ],
      child: MaterialApp(
        title: "HydraCam",
        theme: AppTheme.lightTheme,
        home: const SlaveScreen(isAutoMode: true),
      ),
    );
  }
}
