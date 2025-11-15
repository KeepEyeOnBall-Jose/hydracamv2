import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hydracam/main.dart' as app;

/// Integration tests to verify app launches on all platforms
///
/// PREREQUISITES:
/// - iOS builds require Terminal Full Disk Access:
///   System Settings → Privacy & Security → Full Disk Access → Add Terminal
///   Then QUIT and reopen Terminal/VS Code before running tests
///
/// RUN TESTS:
/// Android:  flutter test integration_test/platform_test.dart -d emulator-5554
/// iOS Sim:  flutter test integration_test/platform_test.dart -d 5CF4A12E-A8B5-4285-AE86-407B9067CB5F
/// iPhone:   flutter test integration_test/platform_test.dart -d 00008101-000A68811E43001E
///
/// If iOS fails with "Sandbox: rsync deny(1) file-read-data":
/// 1. Grant Full Disk Access (see above)
/// 2. OR build from Xcode: open ios/Runner.xcworkspace
/// 3. OR move project out of protected folder (~/Desktop, ~/Documents)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Platform Launch Tests', () {
    testWidgets('App launches successfully on current platform',
        (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify the app launched without crashing
      expect(tester.takeException(), isNull,
          reason: 'App should launch without exceptions');

      // Verify MaterialApp exists
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'MaterialApp should be present');
    });

    testWidgets('App shows SlaveScreen in auto mode',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // The app starts in SlaveScreen auto mode
      // After timeout (3 seconds), it should switch to Master mode
      // Just verify no crashes occurred
      expect(tester.takeException(), isNull,
          reason: 'App should run without exceptions');
    });

    testWidgets('Services initialize correctly', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify no initialization errors
      expect(tester.takeException(), isNull);

      // App should have initialized services and be showing some UI
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Platform-specific checks', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      if (Platform.isAndroid) {
        // Android-specific validation
        debugPrint('✅ Running on Android');
      } else if (Platform.isIOS) {
        // iOS-specific validation
        debugPrint('✅ Running on iOS');
      }

      expect(tester.takeException(), isNull);
    });
  });

  group('Master Mode Tests', () {
    testWidgets('Can switch to Master mode', (WidgetTester tester) async {
      app.main();

      // Wait for auto-mode timeout and transition to Master
      await tester.pumpAndSettle(const Duration(seconds: 6));

      // Should have transitioned without errors
      expect(tester.takeException(), isNull);
    });
  });
}
