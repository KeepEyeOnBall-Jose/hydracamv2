import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/main.dart" as app;
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/settings_service.dart";
import "package:integration_test/integration_test.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final mockClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith("/sessions/create")) {
        return http.Response('{"guid":"integration-session-guid"}', 200,
            headers: {"Content-Type": "application/json"});
      }
      if (path.endsWith("/sessions/end")) {
        return http.Response('{"ok":true}', 200,
            headers: {"Content-Type": "application/json"});
      }
      return http.Response("{}", 200,
          headers: {"Content-Type": "application/json"});
    });

    HydraCamApiService.configureHttpClient(mockClient);
    M2MAuthService.overrideTokenForTests("integration-test-token");
    SettingsService.overrideMasterShouldRecord(false);
    SettingsService.overrideTimerDuration(0);
  });

  tearDownAll(() {
    HydraCamApiService.resetHttpClient();
    SettingsService.clearTestOverrides();
  });

  testWidgets("Master flow can start, command, and end sessions",
      (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final backButton = find.byTooltip("Back");
    expect(backButton, findsOneWidget,
        reason: "Slave screen should render HydraCam app bar");
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Master Mode"));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final startSessionButton =
        find.widgetWithText(ElevatedButton, "Start Session");
    await tester.ensureVisible(startSessionButton);
    await tester.tap(startSessionButton);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining("Session created successfully"), findsOneWidget,
        reason: "User feedback after creating a session should be visible");
    await tester.pumpAndSettle();

    final takePhotoButton = find.widgetWithText(ElevatedButton, "Take Photo");
    await tester.ensureVisible(takePhotoButton);
    await tester.tap(takePhotoButton);
    await tester.pump();
    await tester.pumpAndSettle();

    final startRecordingButton =
        find.widgetWithText(ElevatedButton, "Start Recording");
    await tester.ensureVisible(startRecordingButton);
    await tester.tap(startRecordingButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(ElevatedButton, "Stop Recording"), findsOneWidget,
        reason: "Tapping start should toggle button label");

    final stopRecordingButton =
        find.widgetWithText(ElevatedButton, "Stop Recording");
    await tester.tap(stopRecordingButton);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, "Start Recording"), findsWidgets,
        reason: "Stop should toggle label back");

    final endSessionButton = find.widgetWithText(ElevatedButton, "End Session");
    await tester.ensureVisible(endSessionButton);
    await tester.tap(endSessionButton);
    await tester.pumpAndSettle();

    final confirmEndButton = find.widgetWithText(TextButton, "End Session");
    await tester.tap(confirmEndButton);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining("Capture session ended"), findsOneWidget,
        reason: "Ending a session should show confirmation snackbar");
    await tester.pumpAndSettle();
    expect(startSessionButton, findsOneWidget,
        reason: "UI should return to initial state after ending session");
  });
}
