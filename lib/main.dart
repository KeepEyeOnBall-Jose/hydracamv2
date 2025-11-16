import "package:flutter/material.dart";
import "services/battery_service.dart";
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

  final bool permissionsGranted =
      await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    LogService.instance.registerLog(
        "Some permissions were not granted. The app may not work as expected.");
  }

  final String deviceId = await DeviceIdService.getOrCreateDeviceId();
  LogService.instance.registerLog("Device ID: $deviceId");

  LogService.instance
      .registerLog("Initialize LocationService and try to get the location");
  try {
    final locationService = LocationService();
    await locationService.initialize();
  } catch (e) {
    LogService.instance.registerLog("Failed to initialize location service: $e",
        function: "main()", file: "main.dart");
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

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: "HydraCam",
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          // Initialize services with messenger after MaterialApp builds
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final messenger = scaffoldMessengerKey.currentState;
            if (messenger != null) {
              final storageService = StorageService(
                messengerState: messenger,
                lowStorageThreshold: 1.5,
                criticalStorageThreshold: 0.5,
                onCriticalStorageCallback: () async {
                  LogService.instance.registerLog(
                      "Critical storage: triggering recording stop.");
                  if (CameraServiceSingleton.isInitialized) {
                    await CameraServiceSingleton.instance
                        .forceStopRecordingDueToStorage();
                  }
                },
              );

              CameraServiceSingleton.initialize(storageService);

              BatteryService(
                messengerState: messenger,
                lowBatteryThreshold: 25,
              );
            }
          });
          return const SlaveScreen(isAutoMode: true);
        },
      ),
    );
  }
}
