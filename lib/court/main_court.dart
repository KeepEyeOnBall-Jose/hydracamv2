import "package:flutter/material.dart";

import "../app_theme.dart";
import "../services/log_service.dart";
import "court_channel.dart";
import "court_status_screen.dart";

/// Entry point for the `court` flavor (fixed court camera, K1).
///
/// Must not import the hand-held app's LAN master/slave servers, automation
/// bridge or Auth0 M2M service; `test/court/court_import_graph_test.dart`
/// enforces that.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.instance.registerLog(
    "HydraCam Court UI starting.",
    file: "main_court.dart",
  );
  runApp(CourtApp(channel: CourtChannel()));
}

class CourtApp extends StatelessWidget {
  const CourtApp({super.key, required this.channel});

  final CourtChannel channel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "HydraCam Court",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: CourtStatusScreen(channel: channel),
    );
  }
}
