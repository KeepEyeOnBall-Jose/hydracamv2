import "dart:async";
import "package:battery_plus/battery_plus.dart";
import "package:flutter/material.dart";

import "linux_dbus_availability.dart";
import "log_service.dart";

/// BatteryService monitors battery level and shows warnings when it becomes low.
class BatteryService {
  static BatteryService? _instance;
  static bool _monitoringEnabled = true;

  static BatteryService get instance {
    if (_instance == null) throw Exception("BatteryService not initialized");
    return _instance!;
  }

  final ScaffoldMessengerState _messengerState;
  final int _lowBatteryThreshold;
  final int _criticalBatteryThreshold;
  final FutureOr<void> Function(int currentLevel)? _onCriticalBatteryCallback;
  final Battery _battery = Battery();

  Timer? _batteryCheckTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  DateTime? _lastWarningShownTime;
  int? _lastWarningLevel;
  bool _criticalStopTriggered = false;

  static const Duration _reshowInterval = Duration(minutes: 5);
  static const Duration _pollInterval = Duration(minutes: 1);

  BatteryService({
    required ScaffoldMessengerState messengerState,
    int lowBatteryThreshold = 30,
    int criticalBatteryThreshold = 10,
    FutureOr<void> Function(int currentLevel)? onCriticalBatteryCallback,
  })  : _messengerState = messengerState,
        _lowBatteryThreshold = lowBatteryThreshold,
        _criticalBatteryThreshold = criticalBatteryThreshold,
        _onCriticalBatteryCallback = onCriticalBatteryCallback {
    _startMonitoring();
    _instance = this;
  }

  void _startMonitoring() {
    _batteryCheckTimer?.cancel();
    _batteryStateSubscription?.cancel();

    if (!_monitoringEnabled) {
      LogService.instance.registerLog(
          "BatteryService monitoring disabled - timer not started.");
      return;
    }

    if (LinuxDbusAvailability.shouldSkipSystemBusPlugins) {
      LogService.instance.registerLog(
        "BatteryService monitoring skipped on linux because "
        "${LinuxDbusAvailability.systemBusSocketPath} is unavailable.",
      );
      return;
    }

    _batteryCheckTimer =
        Timer.periodic(_pollInterval, (_) => _checkBatteryLevel());

    _batteryStateSubscription =
        _battery.onBatteryStateChanged.listen((_) => _checkBatteryLevel());

    _checkBatteryLevel();
  }

  Future<void> _checkBatteryLevel() async {
    try {
      final int level = await _battery.batteryLevel;
      _handleBatteryLevel(level);
    } catch (error) {
      LogService.instance
          .registerLog("BatteryService: Error reading battery level: $error");
    }
  }

  void _handleBatteryLevel(int currentLevel) {
    if (currentLevel <= _criticalBatteryThreshold) {
      _handleCriticalBatteryLevel(currentLevel);
      return;
    }

    _criticalStopTriggered = false;

    if (currentLevel < _lowBatteryThreshold) {
      final now = DateTime.now();
      final shouldShow = _shouldShowWarning(now, currentLevel);

      if (shouldShow) {
        _showLowBatteryWarning(currentLevel);
        _lastWarningShownTime = now;
        _lastWarningLevel = currentLevel;
      }
    } else {
      _lastWarningLevel = null;
      _lastWarningShownTime = null;
    }
  }

  void _handleCriticalBatteryLevel(int currentLevel) {
    if (_criticalStopTriggered) {
      return;
    }

    _criticalStopTriggered = true;
    LogService.instance.registerLog(
        "Critical battery: triggering recording stop at $currentLevel%.");
    _showCriticalBatteryWarning(currentLevel);

    final callback = _onCriticalBatteryCallback;
    if (callback != null) {
      unawaited(_runCriticalBatteryCallback(callback, currentLevel));
    }
  }

  Future<void> _runCriticalBatteryCallback(
    FutureOr<void> Function(int currentLevel) callback,
    int currentLevel,
  ) async {
    try {
      await callback(currentLevel);
    } catch (error, stackTrace) {
      LogService.instance.registerError(
        "BatteryService: critical battery callback failed",
        error,
        stackTrace,
      );
    }
  }

  bool _shouldShowWarning(DateTime now, int currentLevel) {
    if (_lastWarningShownTime == null) {
      return true;
    }

    if (_lastWarningLevel != null && _lastWarningLevel != currentLevel) {
      return true;
    }

    if (now.difference(_lastWarningShownTime!) > _reshowInterval) {
      return true;
    }

    return false;
  }

  void _showLowBatteryWarning(int currentLevel) {
    _messengerState.clearSnackBars();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            Icons.battery_alert,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Battery is low ($currentLevel%). Consider plugging in.",
              style: TextStyle(color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.yellow.shade100,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    );

    _messengerState.showSnackBar(snackBar);
  }

  void _showCriticalBatteryWarning(int currentLevel) {
    _messengerState.clearSnackBars();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            Icons.battery_alert,
            color: Colors.red.shade900,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Recording stopped due to critical battery ($currentLevel%).",
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.red.shade100,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
    );

    _messengerState.showSnackBar(snackBar);
  }

  void dispose() {
    _batteryCheckTimer?.cancel();
    _batteryCheckTimer = null;
    _batteryStateSubscription?.cancel();
    _batteryStateSubscription = null;
  }

  @visibleForTesting
  void simulateBatteryLevel(int level) {
    _handleBatteryLevel(level);
  }

  /// Allows widget tests to disable monitoring to avoid MissingPluginExceptions.
  @visibleForTesting
  static void configureMonitoring({required bool enabled}) {
    _monitoringEnabled = enabled;

    if (!enabled) {
      _instance?._batteryCheckTimer?.cancel();
      _instance?._batteryCheckTimer = null;
      _instance?._batteryStateSubscription?.cancel();
      _instance?._batteryStateSubscription = null;
    } else {
      _instance?._startMonitoring();
    }
  }

  @visibleForTesting
  static bool shouldSkipBatteryPluginForTesting({
    required bool isLinux,
    required bool hasSystemBusSocket,
  }) {
    return LinuxDbusAvailability.shouldSkipSystemBusPluginsFor(
      isLinux: isLinux,
      hasSystemBusSocket: hasSystemBusSocket,
    );
  }
}
