import "dart:async";
import "package:flutter/material.dart";
import "package:disk_space_plus/disk_space_plus.dart";
import "log_service.dart";

/// StorageService monitors the device's available storage and shows a warning
/// SnackBar when the storage falls below a defined threshold.
class StorageService {
  static StorageService? _instance;
  static bool _monitoringEnabled = true;

  static StorageService get instance {
    if (_instance == null) throw Exception("StorageService not initialized");
    return _instance!;
  }

  static void setInstance(StorageService s) => _instance = s;

  final ScaffoldMessengerState? _messengerState;
  final double _lowStorageThreshold;
  final double _criticalStorageThreshold;
  final Function() _onCriticalStorageCallback;

  Timer? _storageCheckTimer;
  DateTime? _lastWarningShownTime;
  bool _blockRecording = false;

  static const Duration _reshowInterval = Duration(minutes: 5);

  StorageService({
    required ScaffoldMessengerState? messengerState,
    double lowStorageThreshold = 2.0,
    double criticalStorageThreshold = 0.5,
    required Function() onCriticalStorageCallback,
  })  : _messengerState = messengerState,
        _lowStorageThreshold = lowStorageThreshold,
        _criticalStorageThreshold = criticalStorageThreshold,
        _onCriticalStorageCallback = onCriticalStorageCallback {
    _startMonitoringStorage();
    setInstance(this);
  }

  /// Starts monitoring the device's storage periodically.
  void _startMonitoringStorage() {
    _storageCheckTimer?.cancel();

    if (!_monitoringEnabled) {
      LogService.instance.registerLog(
          "StorageService monitoring disabled - timer not started.");
      return;
    }

    _storageCheckTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final diskSpace = DiskSpacePlus();
        final availableStorage = await diskSpace.getFreeDiskSpace;
        if (availableStorage != null) {
          _handleStorageLevel(availableStorage);
        }
      } catch (error) {
        LogService.instance.registerLog("Error fetching storage info: $error");
      }
    });
  }

  void _handleStorageLevel(double availableStorage) {
    final double availableStorageGB =
        availableStorage / 1024; // Convert MB to GB

    final now = DateTime.now();

    if (availableStorageGB < _criticalStorageThreshold) {
      if (!_blockRecording) {
        _blockRecording = true;
        _onCriticalStorageCallback();
      }
    }

    if (availableStorageGB < _lowStorageThreshold) {
      if (_shouldShowWarning(now)) {
        _showLowStorageWarning(availableStorageGB);
        _lastWarningShownTime = now;
      }
    } else {
      _blockRecording = false;
    }
  }

  bool get isRecordingBlocked => _blockRecording;

  bool _shouldShowWarning(DateTime now) {
    return _lastWarningShownTime == null ||
        now.difference(_lastWarningShownTime!) > _reshowInterval;
  }

  void _showLowStorageWarning(double availableStorage) {
    if (_messengerState == null) return;
    _messengerState!.clearSnackBars();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            Icons.sd_storage,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Low storage available: ${availableStorage.toStringAsFixed(1)} GB. Free up space.",
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.red.shade100,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    );

    _messengerState!.showSnackBar(snackBar);
  }

  void showNotification(String message) {
    if (_messengerState == null) return;
    _messengerState!.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.red.shade100,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @visibleForTesting
  void simulateStorageLevel(double availableStorageMb) {
    _handleStorageLevel(availableStorageMb);
  }

  void dispose() {
    _storageCheckTimer?.cancel();
    _storageCheckTimer = null;
  }

  /// Allows tests to disable or enable periodic monitoring to avoid pending timers.
  @visibleForTesting
  static void configureMonitoring({required bool enabled}) {
    _monitoringEnabled = enabled;

    if (!enabled) {
      _instance?._storageCheckTimer?.cancel();
      _instance?._storageCheckTimer = null;
    } else {
      _instance?._startMonitoringStorage();
    }
  }
}
