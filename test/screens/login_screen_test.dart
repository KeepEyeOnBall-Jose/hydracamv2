import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/login_screen.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets("desktop Auth0 login failure explains mobile-only support",
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.text("Login"));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
          "Auth0 interactive login is only supported on Android and iOS."),
      findsOneWidget,
    );
    expect(find.text("Failed to log in. Please try again."), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
