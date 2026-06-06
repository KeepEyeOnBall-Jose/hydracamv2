import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "app_theme.dart";
import "automation/automation_bridge.dart";
import "automation/automation_config.dart";
import "master/master_screen.dart";
import "services/battery_service.dart";
import "services/camera_service_singleton.dart";
import "services/device_id_provider.dart";
import "services/device_service.dart";
import "services/launch_config_service.dart";
import "services/log_service.dart";
import "services/permission_service.dart";
import "services/storage_service.dart";
import "slave/slave_screen.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (automationEnabled) {
    await AutomationBridge.instance.ensureInitialized();
  }

  final LaunchConfig? launchConfig = await LaunchConfigService.instance.load();

  final bool permissionsGranted =
      await PermissionService.requestAllPermissions();

  if (!permissionsGranted) {
    LogService.instance.registerLog(
        "Some permissions were not granted. The app may not work as expected.");
  }

  final String deviceId = await DeviceIdService.getOrCreateDeviceId();
  LogService.instance.registerLog("Device ID: $deviceId");

  LogService.instance.registerLog(
      "Location access will be requested on demand when the user opens the location view.");

  LogService.instance.registerLog("Prevent screen from turning off");
  WakelockPlus.enable();

  // Initialize CameraServiceSingleton early (before runApp)
  // with a temporary StorageService until we have the messenger
  final tempStorageService = StorageService(
    messengerState: null,
    lowStorageThreshold: 1.5,
    criticalStorageThreshold: 0.5,
    onCriticalStorageCallback: () async {
      LogService.instance
          .registerLog("Critical storage: triggering recording stop.");
      if (CameraServiceSingleton.isInitialized) {
        await CameraServiceSingleton.instance.forceStopRecordingDueToStorage();
      }
    },
  );
  CameraServiceSingleton.initialize(
    tempStorageService,
    useMockCamera: mockCameraEnabled,
  );
  LogService.instance.registerLog(
      "CameraServiceSingleton initialized; mockCamera=$mockCameraEnabled");

  runApp(
    ChangeNotifierProvider(
      create: (_) => DeviceIdProvider(deviceId),
      child: HydraCamApp(launchConfig: launchConfig),
    ),
  );
}

class HydraCamApp extends StatelessWidget {
  const HydraCamApp({super.key, this.launchConfig});

  final LaunchConfig? launchConfig;

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
          // Initialize BatteryService with messenger after MaterialApp builds
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final messenger = scaffoldMessengerKey.currentState;
            if (messenger != null) {
              // Update StorageService with the actual messenger
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
              // Re-initialize with proper messenger for notifications
              CameraServiceSingleton.initialize(
                storageService,
                useMockCamera: mockCameraEnabled,
              );

              BatteryService(
                messengerState: messenger,
                lowBatteryThreshold: 25,
              );
            }
          });

          final LaunchConfig? config = launchConfig;
          final bool automationMaster =
              automationEnabled && (config?.wantsMaster ?? false);
          final bool forceSlave = automationEnabled &&
              ((config?.wantsSlave ?? false) ||
                  (config?.forceSlaveMode ?? false));

          LogService.instance.registerLog(
              "Navigation decision: automationEnabled=$automationEnabled, "
              "config=$config, automationMaster=$automationMaster, "
              "forceSlave=$forceSlave");

          if (automationMaster) {
            LogService.instance.registerLog("Navigating to MasterScreen");
            return const MasterScreen();
          }

          LogService.instance.registerLog(
              "Navigating to SlaveScreen(isAutoMode=${!forceSlave}, "
              "preferredMasterIp=${config?.preferredMasterIp}, "
              "forceSlaveMode=$forceSlave)");
          return SlaveScreen(
            isAutoMode: !forceSlave,
            preferredMasterIp: config?.preferredMasterIp,
            forceSlaveMode: forceSlave,
          );
        },
      ),
    );
  }
}
