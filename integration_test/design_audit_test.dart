import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";

import "package:hydracam/main.dart" as app;
import "package:hydracam/master/master_screen.dart";
import "package:hydracam/screens/settings_screen.dart";

// Runs the real app on hardware, with its real persisted settings and services.
// Never records, uploads, deletes media, or changes a stored preference.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment("AUDIT_PHASE", defaultValue: "before");

  testWidgets("capture real settings and accessibility baselines",
      (tester) async {
    final errors = <String>[];
    Future<void> capture(String name) async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await binding.takeScreenshot(name);
    }

    final testErrorHandler = FlutterError.onError;
    app.main();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(MasterScreen).evaluate().isNotEmpty) break;
    }
    FlutterError.onError = (details) => errors.add(details.toString());
    addTearDown(() {
      FlutterError.onError = testErrorHandler;
      tester.platformDispatcher.clearAllTestValues();
    });
    expect(find.byType(MasterScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await capture("$phase-master");
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump(const Duration(milliseconds: 500));
    await capture("$phase-menu");
    await tester.tap(find.text("Settings").last);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(SettingsScreen), findsOneWidget);
    await capture("$phase-settings");
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pump(const Duration(milliseconds: 500));
    await capture("$phase-info-dialog");
    await tester.tap(find.text("Close"));
    await tester.pump(const Duration(milliseconds: 500));

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
        MediaQuery.textScalerOf(tester.element(find.byType(SettingsScreen)))
            .scale(16),
        32);
    await capture("$phase-settings-text200");
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 500));
    await capture("$phase-settings-text200-scrolled");
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SettingsScreen), findsOneWidget);
    final settingsContext = tester.element(find.byType(SettingsScreen));
    final brightness = Theme.of(settingsContext).brightness;
    if (phase == "after") expect(brightness, Brightness.dark);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, 2000));
    await tester.pump(const Duration(seconds: 1));
    await capture("$phase-settings-dark-requested");
    binding.reportData = {
      ...?binding.reportData,
      "phase": phase,
      "renderedBrightness": brightness.name,
      "source": const String.fromEnvironment("AUDIT_SOURCE",
          defaultValue: "working-tree"),
      "frameworkErrors": errors,
      "appearanceCheck":
          "Test binding requests dark appearance on real hardware",
      "textScaleCheck":
          "Test binding requests 200 percent text on real hardware",
    };
    if (phase == "after") expect(errors, isEmpty);
    FlutterError.onError = testErrorHandler;
  });
}
