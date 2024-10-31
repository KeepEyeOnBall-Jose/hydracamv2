import 'package:flutter/material.dart';
import 'package:sport_cam_sync/screens/role_selection_screen.dart';

void main() {
  runApp(HydraCamApp());
}

/// Main entry point of the application.
class HydraCamApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HydraCam',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: RoleSelectionScreen(), // Set initial screen to role selection
    );
  }
}
