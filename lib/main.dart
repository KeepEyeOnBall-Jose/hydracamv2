import 'package:flutter/material.dart';
import 'master/master_screen.dart';
import 'slave/slave_screen.dart';

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
      home: MasterScreen(), // Set to MasterScreen for now; switch as needed
    );
  }
}
