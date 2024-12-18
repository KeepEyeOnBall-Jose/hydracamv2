/// battery_service.dart
///
/// This service listens to the device's battery status using the `battery_info` package
/// and displays a warning SnackBar (with a battery icon) whenever the battery level
/// falls below a specified threshold (default: 30%).
///
/// Behavior:
/// - The SnackBar will appear regardless of the current screen, since it uses a global
///   ScaffoldMessengerKey to display it.
/// - It will appear whenever the battery goes below the threshold.
/// - If the battery remains below the threshold, it will display again under these conditions:
///   1. If the battery level changes (e.g., from 30% to 29%, 29% to 28%, etc.).
///   2. If the battery level stays the same but at least one minute has passed since the last warning.
///
/// This ensures that if the battery stays low, the user continues to receive periodic warnings,
/// and if the battery decreases further, the user is also warned again immediately.
///
/// Platform behavior:
/// - On Android, it uses `androidBatteryInfoStream`.
/// - On iOS, it uses `iosBatteryInfoStream`.
/// - On other platforms, no subscription is created (no errors).
///
/// Usage:
/// 1. In main.dart, define a GlobalKey<ScaffoldMessengerState> and pass it to BatteryService.initialize.
///    Example:
///
///     final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
///
///     void main() {
///       WidgetsFlutterBinding.ensureInitialized();
///       BatteryService.initialize(
///         scaffoldMessengerKey: scaffoldMessengerKey,
///         lowBatteryThreshold: 30, // optional threshold
///       );
///       runApp(MyApp(scaffoldMessengerKey: scaffoldMessengerKey));
///     }
///
/// 2. Ensure that your MaterialApp is wrapped with the ScaffoldMessenger via:
///
///    MaterialApp(
///      scaffoldMessengerKey: scaffoldMessengerKey,
///      home: MyHomePage(),
///    )
///
/// 3. Whenever the battery level falls below the specified threshold, the SnackBar will appear.
///    If the level stays below, it will appear again every time the level changes or at least once per minute.
///
/// Make sure you have `battery_info` in your pubspec.yaml:
/// dependencies:
///   battery_info: ^1.0.10
///
import 'dart:async';
import 'dart:io' show Platform;
import 'package:battery_info/model/iso_battery_info.dart';
import 'package:flutter/material.dart';
import 'package:battery_info/battery_info_plugin.dart';
import 'package:battery_info/model/android_battery_info.dart';

import 'log_service.dart';

class BatteryService {
  /// Global scaffold messenger key used to show SnackBars across all screens.
  static GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  /// Threshold at which the low battery warning will trigger (in percentage).
  static int _lowBatteryThreshold = 30;

  /// Subscription to the battery info stream.
  static StreamSubscription? _batterySubscription;

  /// Tracks the last time a warning was shown.
  static DateTime? _lastWarningShownTime;

  /// Tracks the last battery level at which a warning was shown.
  static int? _lastWarningLevel;

  /// Minimum interval to re-show warning if the level doesn't change.
  static const Duration _reshowInterval = Duration(minutes: 1);

  // Prevent instantiation.
  BatteryService._();

  /// Initialize the BatteryService.
  ///
  /// [scaffoldMessengerKey]: A GlobalKey<ScaffoldMessengerState> to display SnackBars.
  /// [lowBatteryThreshold]: Battery level (0-100) below which the warning is shown. Defaults to 30.
  static void initialize({
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    int lowBatteryThreshold = 30,
  }) {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _lowBatteryThreshold = lowBatteryThreshold;
    _startListening();
  }

  /// Start listening to the battery info stream depending on the platform.
  static void _startListening() {
    _batterySubscription?.cancel();
    _batterySubscription = null;

    final batteryPlugin = BatteryInfoPlugin();

    if (Platform.isAndroid) {
      _batterySubscription = batteryPlugin.androidBatteryInfoStream.listen(
            (AndroidBatteryInfo? info) {
          if (info == null || info.batteryLevel == null) return;
          _handleBatteryLevel(info.batteryLevel!);
        },
        onError: (error) {
          LogService.instance.registerLog('Error listening to Android battery info: $error');
        },
      );
    } else if (Platform.isIOS) {
      _batterySubscription = batteryPlugin.iosBatteryInfoStream.listen(
            (IosBatteryInfo? info) {
          if (info == null || info.batteryLevel == null) return;
          _handleBatteryLevel(info.batteryLevel!);
        },
        onError: (error) {
          LogService.instance.registerLog('Error listening to iOS battery info: $error');
        },
      );
    } else {
      LogService.instance.registerLog('BatteryService: Platform not supported by battery_info. No streaming started.');
    }
  }

  /// Handle battery level changes and decide whether to show a warning.
  static void _handleBatteryLevel(int currentLevel) {
    if (currentLevel < _lowBatteryThreshold) {
      final now = DateTime.now();
      final shouldShow = _shouldShowWarning(now, currentLevel);

      if (shouldShow) {
        _showLowBatteryWarning(currentLevel);
        _lastWarningShownTime = now;
        _lastWarningLevel = currentLevel;
      }
    } else {
      // If battery goes back above threshold, reset the tracking.
      _lastWarningLevel = null;
      _lastWarningShownTime = null;
    }
  }

  /// Determines if the warning should be shown based on:
  /// - If no warning was shown before.
  /// - If the battery level has changed since the last warning.
  /// - If at least 1 minute has passed since the last warning, even if level is unchanged.
  static bool _shouldShowWarning(DateTime now, int currentLevel) {
    if (_lastWarningShownTime == null) {
      // No warning has been shown yet.
      return true;
    }

    // If the battery level changed (e.g. from 30% to 29%) show the warning again immediately.
    if (_lastWarningLevel != null && _lastWarningLevel != currentLevel) {
      return true;
    }

    // If the battery level stays the same but at least 1 minute has passed, show the warning again.
    if (now.difference(_lastWarningShownTime!) > _reshowInterval) {
      return true;
    }

    return false;
  }

  /// Displays the low battery warning SnackBar.
  static void _showLowBatteryWarning(int currentLevel) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger == null) return;

    messenger.clearSnackBars();

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
              'Battery is low ($currentLevel%). Consider plugging in.',
              style: TextStyle(color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.yellow.shade100,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    );

    messenger.showSnackBar(snackBar);
  }

  /// Dispose of the subscription if needed (e.g. on app exit).
  static void dispose() {
    _batterySubscription?.cancel();
    _batterySubscription = null;
  }
}
