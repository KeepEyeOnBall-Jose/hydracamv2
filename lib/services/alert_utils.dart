/// A CLASS THAT EXTRACTS THE LOGIC OF SHOWING ALERTS, POP UPS, LOADING MESSAGES...


import 'package:flutter/material.dart';
import '../app_theme.dart';

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
                  CircularProgressIndicator(
                    color: AppTheme.accentColor, // Use accent color for loader
                  ),
                  SizedBox(height: 20),
                  Text(
                    title,
                    style: AppTheme.headline1.copyWith(fontSize: 20), // Title style
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
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