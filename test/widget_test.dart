import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:hydracam/automation/automation_screenshot_service.dart";
import "package:hydracam/main.dart";
import "package:hydracam/master/master_screen.dart";
import "package:hydracam/services/battery_service.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/storage_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    StorageService.configureMonitoring(enabled: false);
    BatteryService.configureMonitoring(enabled: false);
    CameraServiceSingleton.initialize(
      StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      ),
      useMockCamera: true,
    );
  });

  tearDownAll(() {
    StorageService.configureMonitoring(enabled: true);
    BatteryService.configureMonitoring(enabled: true);
  });

  testWidgets("HydraCamApp builds without crashing",
      (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const HydraCamApp());

    // Simple smoke test: the app should build and show a MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets("automation screenshot boundary survives route replacement",
      (WidgetTester tester) async {
    await tester.pumpWidget(const HydraCamApp());
    await tester.pumpAndSettle();

    expect(
      AutomationScreenshotService.repaintBoundaryKey.currentContext,
      isNotNull,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MasterScreen()),
      (_) => false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterScreen), findsOneWidget);
    expect(
      AutomationScreenshotService.repaintBoundaryKey.currentContext,
      isNotNull,
    );
  });
}
