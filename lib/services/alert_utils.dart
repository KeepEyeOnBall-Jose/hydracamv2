/// A CLASS THAT EXTRACTS THE LOGIC OF SHOWING ALERTS, POP UPS, LOADING MESSAGES...
library;

import "dart:io";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "../app_theme.dart";
import "../models/captured_photo.dart";
import "../master/master_screen.dart";
import "device_service.dart";
import "location_service.dart";

// ignore: avoid_classes_with_only_static_members
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
        return PopScope(
          canPop: false, // Prevent closing with the back button
          child: Dialog(
            backgroundColor: Colors.white.withValues(alpha: 0.9), // White translucent background
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

  /// Displays a dialog for showing a photo or video.
  /// Automatically adjusts to the screen size and supports auto-closing for master screens.
 static void showMediaDialog({
    required BuildContext context,
    required dynamic media, // CapturedPhoto or CapturedVideo
    required bool isAutoCloseEnabled, // Auto-close for master screens
    int autoCloseSeconds = 5, // Default auto-close time
  }) {
    final isPhoto = media is CapturedPhoto;
    final filePath = isPhoto ? media.photoPath : media.videoPath;

    // Check if the file exists
    final file = File(filePath);
    if (!file.existsSync()) {
      AlertUtils.showFileMissingDialog(isPhoto ? "Photo" : "Video", context);
      return;
    }

    // Flag to track if the dialog is open
    bool isDialogOpen = true;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16.0), // Space from screen edges
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8, // 80% height
              maxWidth: MediaQuery.of(context).size.width * 0.9,  // 90% width
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Media viewer
                Expanded(
                  child: isPhoto
                      ? Image.file(file, fit: BoxFit.contain) // Show photo
                      : AspectRatio(
                    aspectRatio: 16 / 9, // Default video aspect ratio
                    child: VideoPlayerScreen(videoPath: filePath), // Show video
                  ),
                ),
                // Close button
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      isDialogOpen = false;
                      Navigator.pop(context);
                    },
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      // When the dialog is closed (manually or automatically), mark it as closed
      isDialogOpen = false;
    });

    // Auto-close logic for master screens
    if (isAutoCloseEnabled) {
      Future.delayed(Duration(seconds: autoCloseSeconds), () {
        // ignore: use_build_context_synchronously
        if (isDialogOpen && Navigator.canPop(context)) {
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      });
    }
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
              final Map<String, dynamic> deviceInfo = snapshot.data!;
              return AlertDialog(
                title: const Text("Device Information"),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: deviceInfo.entries.map((entry) {
                      return Text("${entry.key}: ${entry.value}");
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
    final Position? position = locationService.currentPosition;
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

  static void showUploadedMediaAlert(BuildContext context, String mediaPath) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Media Already Uploaded"),
          content: Text("The file at $mediaPath has already been uploaded."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  static void showUploadAllMediaAlert(
      BuildContext context, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Upload Unsent Media"),
          content: const Text(
              "Do you want to load this session and upload all unsent media?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                onConfirm(); // Execute the action
              },
              child: const Text("Confirm"),
            ),
          ],
        );
      },
    );
  }


  static void showMasterSnackBar(BuildContext context, String message) {
    final messengerState = ScaffoldMessenger.of(context);

    // Show the SnackBar
    messengerState.clearSnackBars();
    messengerState.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.red.shade100,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
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


