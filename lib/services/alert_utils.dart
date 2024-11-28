/// A CLASS THAT EXTRACTS THE LOGIC OF SHOWING ALERTS, POP UPS, LOADING MESSAGES...


import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../app_theme.dart';
import 'device_service.dart';
import 'location_service.dart';

class AlertUtils {
  /// Displays a loading dialog with a custom title and message.
  static void showLoadingDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent closing with the back button
          child: Dialog(
            backgroundColor: Colors.white.withOpacity(0.9), // White translucent background
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: AppTheme.accentColor, // Use accent color for loader
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: AppTheme.headline1.copyWith(fontSize: 20), // Title style
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: AppTheme.bodyText1.copyWith(color: AppTheme.accentColor), // Message style
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Closes the currently displayed dialog.
  static void dismissDialog(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Shows an informational dialog with a title and message.
  static void showInfoDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title, style: AppTheme.headline1),
          content: Text(message, style: AppTheme.bodyText1),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
              ),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  /// ------------------
  /// SPECIFIC DIALOGS
  /// ------------------

  /// Show dialog with info about device.
  static void showDeviceInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: DeviceIdService.getDeviceInfo(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: const Text("Device Information"),
                content: const Center(
                  child: CircularProgressIndicator(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                    ),
                    child: const Text("Close"),
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return AlertDialog(
                title: const Text("Device Information"),
                content: const Text("Error when obtaining the device information."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                    ),
                    child: const Text("Close"),
                  ),
                ],
              );
            } else {
              Map<String, dynamic> deviceInfo = snapshot.data!;
              return AlertDialog(
                title: const Text("Device Information"),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: deviceInfo.entries.map((entry) {
                      return Text('${entry.key}: ${entry.value}');
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                    ),
                    child: const Text("Close"),
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }

  /// Show dialog with info about device location.
  static Future<void> showLocationInfoDialog(BuildContext context) async {
    final locationService = LocationService(); // Access the singleton instance

    // Fetch the latest location or fallback to "not available"
    String locationInfo;
    Position? position = locationService.currentPosition;
    if (position != null) {
      locationInfo = "Latitude: ${position.latitude}\n"
          "Longitude: ${position.longitude}\n"
          "Precision: ${position.accuracy} metres";
    } else {
      locationInfo = "Location unavailable.";
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Device Location"),
          content: Text(locationInfo),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentColor,
              ),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }


  /// Show dialog when trying to open a deleted media file.
  static void showFileMissingDialog(String fileType, BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("$fileType Not Found"),
          content: Text("The selected $fileType file is no longer available on this device."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

}

// Use example
/*
AlertUtils.showLoadingDialog(
  context: context,
  title: "Loading",
  message: "Please wait while we process your request...",
);
*/

// To close dialog
/*
AlertUtils.dismissDialog(context);
*/


