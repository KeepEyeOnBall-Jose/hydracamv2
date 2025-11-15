import "dart:async";
// import "dart:io" show Platform;
// import "package:battery_info/model/iso_battery_info.dart";
import "package:flutter/material.dart";
// import "package:battery_info/battery_info_plugin.dart";
// import "package:battery_info/model/android_battery_info.dart";

import "log_service.dart";

// Battery service temporarily disabled due to battery_info plugin incompatibility with current Android Gradle
class BatteryService {
  final ScaffoldMessengerState _messengerState;
  final int _lowBatteryThreshold;

  StreamSubscription? _batterySubscription;
  DateTime? _lastWarningShownTime;
  int? _lastWarningLevel;

  static const Duration _reshowInterval = Duration(minutes: 1);

  BatteryService({
    required ScaffoldMessengerState messengerState,
    int lowBatteryThreshold = 30,
  })  : _messengerState = messengerState,
        _lowBatteryThreshold = lowBatteryThreshold {
    _startListening();
  }

  void _startListening() {
    // Battery monitoring temporarily disabled - battery_info plugin incompatible with current Android Gradle
    LogService.instance.registerLog(
        "BatteryService: Temporarily disabled due to plugin incompatibility");
    /*
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
          LogService.instance.registerLog("Error listening to Android battery info: $error");
        },
      );
    } else if (Platform.isIOS) {
      _batterySubscription = batteryPlugin.iosBatteryInfoStream.listen(
        (IosBatteryInfo? info) {
          if (info == null || info.batteryLevel == null) return;
          _handleBatteryLevel(info.batteryLevel!);
        },
        onError: (error) {
          LogService.instance.registerLog("Error listening to iOS battery info: $error");
        },
      );
    } else {
      LogService.instance.registerLog("BatteryService: Platform not supported by battery_info. No streaming started.");
    }
    */
  }

  void _handleBatteryLevel(int currentLevel) {
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

  void dispose() {
    _batterySubscription?.cancel();
    _batterySubscription = null;
  }
}
