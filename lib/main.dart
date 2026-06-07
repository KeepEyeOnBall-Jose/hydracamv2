import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "app_theme.dart";
import "automation/automation_bridge.dart";
import "automation/automation_config.dart";
import "automation/automation_standby_screen.dart";
import "automation/runtime_role_switch.dart";
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

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.instance.registerLog(
          "Flutter framework error: ${details.exceptionAsString()}\n"
          "${details.stack}");
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      LogService.instance.registerError(
          "Uncaught platform dispatcher error", error, stackTrace);
      return false;
    };

    if (automationEnabled) {
      await AutomationBridge.instance.ensureInitialized();
    }

    final LaunchConfig? launchConfig =
        await LaunchConfigService.instance.load();

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
          await CameraServiceSingleton.instance
              .forceStopRecordingDueToStorage();
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
  }, (error, stackTrace) {
    LogService.instance.registerError("Uncaught zone error", error, stackTrace);
  });
}

class HydraCamApp extends StatefulWidget {
  const HydraCamApp({super.key, this.launchConfig});

  final LaunchConfig? launchConfig;

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  State<HydraCamApp> createState() => _HydraCamAppState();
}

class _HydraCamAppState extends State<HydraCamApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    if (automationEnabled) {
      AutomationBridge.instance.registerCommand(
        "set_role",
        _handleSetRuntimeRole,
      );
    }
  }

  @override
  void dispose() {
    if (automationEnabled) {
      AutomationBridge.instance.unregisterCommands(["set_role"]);
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _handleSetRuntimeRole(
      Map<String, dynamic> payload) async {
    final request = RuntimeRoleSwitchRequest.fromPayload(payload);
    await _switchRuntimeRole(request);
    return {
      ...request.toJson(),
      "status": "role_set",
    };
  }

  Future<void> _switchRuntimeRole(RuntimeRoleSwitchRequest request) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw StateError("Navigator is not ready for runtime role switch.");
    }

    LogService.instance
        .registerLog("Runtime role switch requested: ${request.toJson()}");
    unawaited(navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _screenForRuntimeRole(request),
      ),
      (_) => false,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Widget _screenForRuntimeRole(RuntimeRoleSwitchRequest request) {
    switch (request.role) {
      case RuntimeAutomationRole.master:
        return const MasterScreen();
      case RuntimeAutomationRole.slave:
        return SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: request.preferredMasterIp,
          forceSlaveMode: request.forceSlaveMode,
        );
      case RuntimeAutomationRole.standby:
        return const AutomationStandbyScreen();
    }
  }

  Widget _initialScreen() {
    final LaunchConfig? config = widget.launchConfig;
    final bool automationMaster =
        automationEnabled && (config?.wantsMaster ?? false);
    final bool automationStandby =
        automationEnabled && (config?.wantsStandby ?? false);
    final bool forceSlave = automationEnabled &&
        ((config?.wantsSlave ?? false) || (config?.forceSlaveMode ?? false));

    LogService.instance.registerLog(
        "Navigation decision: automationEnabled=$automationEnabled, "
        "config=$config, automationMaster=$automationMaster, "
        "automationStandby=$automationStandby, forceSlave=$forceSlave");

    if (automationMaster) {
      LogService.instance.registerLog("Navigating to MasterScreen");
      return const MasterScreen();
    }

    if (automationStandby) {
      LogService.instance.registerLog("Navigating to AutomationStandbyScreen");
      return const AutomationStandbyScreen();
    }

    LogService.instance
        .registerLog("Navigating to SlaveScreen(isAutoMode=${!forceSlave}, "
            "preferredMasterIp=${config?.preferredMasterIp}, "
            "forceSlaveMode=$forceSlave)");
    return SlaveScreen(
      isAutoMode: !forceSlave,
      preferredMasterIp: config?.preferredMasterIp,
      forceSlaveMode: forceSlave,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: HydraCamApp.scaffoldMessengerKey,
      title: "HydraCam",
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          // Initialize BatteryService with messenger after MaterialApp builds
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final messenger = HydraCamApp.scaffoldMessengerKey.currentState;
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

          return _initialScreen();
        },
      ),
    );
  }
}
