import 'dart:async';
import 'package:flutter/material.dart';
import 'package:disk_space_plus/disk_space_plus.dart'; // Updated dependency
import 'log_service.dart';

/// StorageService monitors the device's available storage and shows a warning
/// SnackBar when the storage falls below a defined threshold.
class StorageService {
  /// Global scaffold messenger key used to show SnackBars across all screens.
  static GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  /// Threshold at which the low storage warning will trigger (in gigabytes).
  static double _lowStorageThreshold = 2.0; // Default threshold: 2GB

  /// Timer for periodic storage checks.
  static Timer? _storageCheckTimer;

  /// Tracks the last time a warning was shown.
  static DateTime? _lastWarningShownTime;

  /// Minimum interval to re-show warning if the storage remains low.
  static const Duration _reshowInterval = Duration(minutes: 5);

  /// Flag and callback to stop recording when storage is critically low
  static bool _blockRecording = false; // Prevents further recording if storage is critical
  static Function()? _onCriticalStorageCallback; // Callback to stop recording

  /// Prevent instantiation.
  StorageService._();

  /// Critical threshold at which recording stops automatically (in gigabytes).
  static double _criticalStorageThreshold = 0.5; // Default critical threshold: 0.5GB


  /// Initialize the StorageService.
  ///
  /// [scaffoldMessengerKey]: A GlobalKey<ScaffoldMessengerState> to display SnackBars.
  /// [lowStorageThreshold]: Storage threshold in GB below which the warning is shown. Defaults to 2GB.
  /// [criticalStorageThreshold]: Threshold in GB for triggering critical storage actions. Defaults to 0.5GB
  static void initialize({
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    double lowStorageThreshold = 2.0,
    double criticalStorageThreshold = 0.5,
    required Function() onCriticalStorageCallback,
  }) {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _lowStorageThreshold = lowStorageThreshold;
    _criticalStorageThreshold = criticalStorageThreshold;
    _onCriticalStorageCallback = onCriticalStorageCallback;
    _startMonitoringStorage();
  }

  /// Starts monitoring the device's storage periodically.
  static void _startMonitoringStorage() {
    // Cancel any existing timer.
    _storageCheckTimer?.cancel();

    // Check storage every 1 minute.
    _storageCheckTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        final availableStorage = await DiskSpacePlus.getFreeDiskSpace;
        if (availableStorage != null) {
          _handleStorageLevel(availableStorage);
        }
      } catch (error) {
        LogService.instance.registerLog('Error fetching storage info: $error');
      }
    });
  }

  /// Handles the available storage level and determines whether to show a warning.
  static void _handleStorageLevel(double availableStorage) {

    double availableStorageGB = availableStorage / 1024; // Convert MB to GB

    print("Storage level: $availableStorageGB GB");
    final now = DateTime.now();

    // Check critical threshold
    if (availableStorageGB < _criticalStorageThreshold) {
      if (!_blockRecording) {
        _blockRecording = true;
        _onCriticalStorageCallback?.call(); // Trigger critical storage callback
      }
    }

    // Check low storage warning threshold
    if (availableStorageGB < _lowStorageThreshold) {
      if (_shouldShowWarning(now)) {
        _showLowStorageWarning(availableStorageGB);
        _lastWarningShownTime = now;
      }
    } else {
      // Reset block flag if storage improves
      _blockRecording = false;
    }
  }

  static bool get isRecordingBlocked => _blockRecording;

  /// Determines if a low storage warning should be shown based on:
  /// - Whether enough time has passed since the last warning.
  static bool _shouldShowWarning(DateTime now) {
    return _lastWarningShownTime == null ||
        now.difference(_lastWarningShownTime!) > _reshowInterval;
  }

  /// Displays the low storage warning SnackBar.
  static void _showLowStorageWarning(double availableStorage) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger == null) return;

    messenger.clearSnackBars();

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
              'Low storage available: ${availableStorage.toStringAsFixed(1)} GB. Free up space.',
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.red.shade100,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    );

    messenger.showSnackBar(snackBar);
  }

  /// Displays a custom notification. Tipially invoked from camera service on low space.
  static void showNotification(String message) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message ,style: const TextStyle(
            color: Colors.black
          )),
          backgroundColor: Colors.red.shade100,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Dispose of the timer when the app is closed or service is no longer needed.
  static void dispose() {
    _storageCheckTimer?.cancel();
    _storageCheckTimer = null;
  }
}