import 'package:flutter/material.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';

void main() {
  runApp(SportCamSyncApp());
}

/// Main entry point of the application.
class SportCamSyncApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportCamSync',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: RoleSelectionScreen(), // Set initial screen to role selection
    );
  }
}
