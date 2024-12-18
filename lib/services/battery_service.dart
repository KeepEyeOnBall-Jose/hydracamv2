/// battery_service.dart
///
/// This service listens to the device's battery status using the `battery_info` package
/// and displays a warning SnackBar (with a battery icon) whenever the battery level
/// falls below a specified threshold (default: 30%).
///
/// The SnackBar will appear regardless of the current screen, since it uses a global
/// ScaffoldMessengerKey to display it. This is achieved by providing a GlobalKey<ScaffoldMessengerState>
/// at initialization time.
///
/// This service is platform-aware:
/// - On Android, it uses `androidBatteryInfoStream` to listen for updates.
/// - On iOS, it uses `iosBatteryInfoStream` to listen for updates.
/// - On other platforms, it won't break; it will simply not start any subscription.
///
/// Usage:
/// 1. In your main.dart, define a GlobalKey<ScaffoldMessengerState> and pass it to
///    BatteryService when initializing the app.
///
///    Example:
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
/// 3. Now, whenever the battery level falls below the specified threshold,
///    a SnackBar with a warning battery icon will appear, regardless of the current screen.
///
/// Note: `battery_info` currently provides different streams for Android and iOS.
///       If needed, add platform checks using `dart:io`.
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

class BatteryService {
  /// The global scaffold messenger key used to show SnackBars across all screens.
  static GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  /// Threshold at which the low battery warning will trigger.
  static int _lowBatteryThreshold = 30;

  /// Internal subscription to battery info stream.
  static StreamSubscription? _batterySubscription;

  /// Indicates if we have already shown the warning Snackbar to avoid repeated pop-ups.
  static bool _lowBatteryWarningShown = false;

  // Prevent instantiation.
  BatteryService._();

  /// Initializes the BatteryService.
  ///
  /// [scaffoldMessengerKey]: A GlobalKey<ScaffoldMessengerState> to show SnackBars.
  /// [lowBatteryThreshold]: The percentage level below which a warning will appear. Default is 30.
  static void initialize({
    required GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
    int lowBatteryThreshold = 30,
  }) {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    _lowBatteryThreshold = lowBatteryThreshold;
    _startListening();
  }

  /// Starts listening to battery info stream depending on the platform.
  static void _startListening() {
    // Stop any existing subscriptions if re-initialized.
    _batterySubscription?.cancel();
    _batterySubscription = null;

    final batteryPlugin = BatteryInfoPlugin();

    if (Platform.isAndroid) {
      // Android: listen to androidBatteryInfoStream
      _batterySubscription = batteryPlugin.androidBatteryInfoStream.listen(
            (AndroidBatteryInfo? info) {
          if (info == null) return;
          final level = info.batteryLevel;
          if (level == null) return;
          _handleBatteryLevel(level);
        },
        onError: (error) {
          // If there's an error in the stream, we log it (optional)
          debugPrint('Error listening to Android battery info: $error');
        },
      );
    } else if (Platform.isIOS) {
      // iOS: listen to iosBatteryInfoStream
      _batterySubscription = batteryPlugin.iosBatteryInfoStream.listen(
            (IosBatteryInfo? info) {
          if (info == null) return;
          final level = info.batteryLevel;
          if (level == null) return;
          _handleBatteryLevel(level);
        },
        onError: (error) {
          // If there's an error in the stream, we log it (optional)
          debugPrint('Error listening to iOS battery info: $error');
        },
      );
    } else {
      // Other platforms are not supported by this plugin.
      // No subscription is created to avoid errors.
      debugPrint('BatteryService: Platform not supported by battery_info. No streaming started.');
    }
  }

  /// Handles the battery level changes and shows/hides Snackbar accordingly.
  static void _handleBatteryLevel(int currentLevel) {
    if (currentLevel < _lowBatteryThreshold && !_lowBatteryWarningShown) {
      _showLowBatteryWarning(currentLevel);
      _lowBatteryWarningShown = true;
    } else if (currentLevel >= _lowBatteryThreshold) {
      // Reset warning state if battery goes back above threshold
      _lowBatteryWarningShown = false;
    }
  }

  /// Displays a low battery warning SnackBar with an icon.
  static void _showLowBatteryWarning(int currentLevel) {
    final messenger = _scaffoldMessengerKey?.currentState;
    if (messenger == null) return;

    // Remove any previous SnackBars before showing a new one.
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

  /// Call this to dispose of the subscription if needed (e.g. on app exit).
  static void dispose() {
    _batterySubscription?.cancel();
    _batterySubscription = null;
  }
}
