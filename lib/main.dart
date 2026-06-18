import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:wakelock_plus/wakelock_plus.dart";

import "app_theme.dart";
import "automation/automation_bridge.dart";
import "automation/automation_config.dart";
import "automation/automation_screenshot_service.dart";
import "automation/automation_standby_screen.dart";
import "automation/runtime_role_switch.dart";
import "l10n/app_localizations.dart";
import "master/master_screen.dart";
import "screens/camera_setup_preview_screen.dart";
import "services/app_locale_service.dart";
import "services/battery_service.dart";
import "services/camera_service_singleton.dart";
import "services/device_id_provider.dart";
import "services/device_service.dart";
import "services/hydracam_api_service.dart";
import "services/launch_config_service.dart";
import "services/linux_dbus_availability.dart";
import "services/log_service.dart";
import "services/permission_service.dart";
import "services/storage_service.dart";
import "services/user_service.dart";
import "slave/slave_screen.dart";

typedef BackendWarmUpCallback = Future<bool> Function();

@visibleForTesting
void startBackendWarmUp({BackendWarmUpCallback? warmUpBackend}) {
  unawaited((warmUpBackend ?? HydraCamApiService().warmUpBackend)());
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.instance
          .registerLog("Flutter framework error: ${details.toString()}");
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      LogService.instance.registerError(
          "Uncaught platform dispatcher error", error, stackTrace);
      return false;
    };

    startBackendWarmUp();

    final LaunchConfig? launchConfig =
        await LaunchConfigService.instance.load();
    await _enableScreenWakeLock("startup");
    if (automationEnabled) {
      AutomationBridge.instance.setAutomationTargetId(launchConfig?.targetId);
      await AutomationBridge.instance.ensureInitialized();
    }

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

    final bool restoredUserSession = await UserService().restoreStoredSession();
    if (restoredUserSession) {
      LogService.instance
          .registerLog("Restored persisted user session during startup.");
    }
    final localeService = AppLocaleService.instance;
    await localeService.load();

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
        child: HydraCamApp(
          launchConfig: launchConfig,
          localeService: localeService,
        ),
      ),
    );
  }, (error, stackTrace) {
    LogService.instance.registerError("Uncaught zone error", error, stackTrace);
  });
}

Future<void> _enableScreenWakeLock(String reason) async {
  if (LinuxDbusAvailability.shouldSkipSessionBusPlugins) {
    LogService.instance.registerLog(
      "Skipping wakelock on linux because no DBus session bus is available "
      "($reason).",
    );
    return;
  }

  try {
    await WakelockPlus.enable();
    LogService.instance.registerLog(
        "Prevent screen from turning off: wakelock enabled ($reason)");
  } catch (error, stackTrace) {
    LogService.instance.registerError(
      "Failed to enable wakelock ($reason)",
      error,
      stackTrace,
    );
  }
}

class HydraCamApp extends StatefulWidget {
  const HydraCamApp({
    super.key,
    this.launchConfig,
    AppLocaleService? localeService,
  }) : _localeService = localeService;

  final LaunchConfig? launchConfig;
  final AppLocaleService? _localeService;

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  State<HydraCamApp> createState() => _HydraCamAppState();
}

class _HydraCamAppState extends State<HydraCamApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLocaleService _localeService =
      widget._localeService ?? AppLocaleService.instance;
  late final AutomationHandler _setRoleAutomationHandler =
      _handleSetRuntimeRole;
  late final AutomationHandler _captureScreenshotAutomationHandler =
      AutomationScreenshotService.capture;
  bool _automationRouteActive = false;

  @override
  void initState() {
    super.initState();
    _automationRouteActive = _isAutomationRouteConfig(widget.launchConfig);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableScreenWakeLock("app init"));
    if (automationEnabled) {
      AutomationBridge.instance.registerCommand(
        "set_role",
        _setRoleAutomationHandler,
      );
      AutomationBridge.instance.registerCommand(
        "capture_screenshot",
        _captureScreenshotAutomationHandler,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (automationEnabled) {
      AutomationBridge.instance.unregisterCommandsIfCurrent({
        "set_role": _setRoleAutomationHandler,
        "capture_screenshot": _captureScreenshotAutomationHandler,
      });
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enableScreenWakeLock("app resumed"));
      unawaited(_openNormalAppAfterManualLauncherStart());
    }
  }

  Future<Map<String, dynamic>> _handleSetRuntimeRole(
      Map<String, dynamic> payload) async {
    final request = RuntimeRoleSwitchRequest.fromPayload(payload);
    final shouldAcknowledgeAccepted = payload["ackMode"] == "accepted";
    if (shouldAcknowledgeAccepted) {
      _ensureNavigatorReady();
      unawaited(_switchRuntimeRole(request)
          .catchError((Object error, StackTrace stackTrace) {
        LogService.instance.registerError(
          "Async runtime role switch failed",
          error,
          stackTrace,
        );
      }));
      return {
        ...request.toJson(),
        "status": "role_switch_accepted",
        "ackMode": "accepted",
      };
    }
    await _switchRuntimeRole(request);
    return {
      ...request.toJson(),
      "status": "role_set",
    };
  }

  NavigatorState _ensureNavigatorReady() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      throw StateError("Navigator is not ready for runtime role switch.");
    }
    return navigator;
  }

  Future<void> _switchRuntimeRole(RuntimeRoleSwitchRequest request) async {
    final navigator = _ensureNavigatorReady();

    LogService.instance
        .registerLog("Runtime role switch requested: ${request.toJson()}");
    unawaited(_enableScreenWakeLock("runtime role switch"));
    _automationRouteActive = true;
    navigator.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => _screenForRuntimeRole(request),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (_) => false,
    );
    await WidgetsBinding.instance.endOfFrame;
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
        return _automationStandbyScreen();
    }
  }

  Widget _automationStandbyScreen() {
    return AutomationStandbyScreen(
      onOpenNormalApp: () {
        unawaited(_openNormalApp());
      },
    );
  }

  bool _isAutomationRouteConfig(LaunchConfig? config) {
    if (!automationEnabled || config == null || config.isManualLaunch) {
      return false;
    }
    return config.wantsMaster ||
        config.wantsSlave ||
        config.wantsStandby ||
        config.wantsSetupPreview ||
        config.forceSlaveMode;
  }

  Future<void> _openNormalAppAfterManualLauncherStart() async {
    if (!automationEnabled || !_automationRouteActive) {
      return;
    }

    final LaunchConfig? config = await LaunchConfigService.instance.load();
    if (!(config?.isManualLaunch ?? false)) {
      return;
    }

    LogService.instance.registerLog(
        "Manual launcher start detected while automation route was active.");
    await _openNormalApp();
  }

  Future<void> _openNormalApp() async {
    await LaunchConfigService.instance.clearSavedAutomationLaunchConfig();
    if (!mounted) {
      return;
    }

    _automationRouteActive = false;
    LogService.instance
        .registerLog("Opening normal HydraCam app from automation standby.");
    _ensureNavigatorReady().pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const SlaveScreen(isAutoMode: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (_) => false,
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  Widget _initialScreen() {
    final LaunchConfig? config = widget.launchConfig;
    final bool automationMaster =
        automationEnabled && (config?.wantsMaster ?? false);
    final bool automationStandby =
        automationEnabled && (config?.wantsStandby ?? false);
    final bool automationSetupPreview =
        automationEnabled && (config?.wantsSetupPreview ?? false);
    final bool forceSlave = automationEnabled &&
        ((config?.wantsSlave ?? false) || (config?.forceSlaveMode ?? false));

    LogService.instance.registerLog(
        "Navigation decision: automationEnabled=$automationEnabled, "
        "config=$config, automationMaster=$automationMaster, "
        "automationStandby=$automationStandby, "
        "automationSetupPreview=$automationSetupPreview, "
        "forceSlave=$forceSlave");

    if (automationMaster) {
      LogService.instance.registerLog("Navigating to MasterScreen");
      return const MasterScreen();
    }

    if (automationStandby) {
      LogService.instance.registerLog("Navigating to AutomationStandbyScreen");
      return _automationStandbyScreen();
    }

    if (automationSetupPreview) {
      LogService.instance
          .registerLog("Navigating to CameraSetupStandaloneScreen");
      return CameraSetupStandaloneScreen(onOpenNormalApp: _openNormalApp);
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
    return ListenableBuilder(
      listenable: _localeService,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: HydraCamApp.scaffoldMessengerKey,
          title: "HydraCam",
          theme: AppTheme.lightTheme,
          locale: _localeService.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            // Initialize BatteryService with messenger after MaterialApp builds.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final messenger = HydraCamApp.scaffoldMessengerKey.currentState;
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
                CameraServiceSingleton.initialize(
                  storageService,
                  useMockCamera: mockCameraEnabled,
                );

                BatteryService(
                  messengerState: messenger,
                  lowBatteryThreshold: 25,
                  criticalBatteryThreshold: 10,
                  onCriticalBatteryCallback: (_) async {
                    LogService.instance.registerLog(
                        "Critical battery: triggering recording stop.");
                    if (CameraServiceSingleton.isInitialized) {
                      await CameraServiceSingleton.instance
                          .forceStopRecordingDueToBattery();
                    }
                  },
                );
              }
            });

            return RepaintBoundary(
              key: AutomationScreenshotService.repaintBoundaryKey,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _initialScreen(),
        );
      },
    );
  }
}
