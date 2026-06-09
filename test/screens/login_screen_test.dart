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

  testWidgets("account deletion request dialog is available before login",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.text("Request Account Deletion"));
    await tester.pumpAndSettle();

    expect(find.text("Account Deletion"), findsOneWidget);
    expect(find.textContaining("HydraCam account deletion request"),
        findsOneWidget);
    expect(find.textContaining("Login email: unknown"), findsOneWidget);

    await tester.tap(find.text("Copy Request"));
    await tester.pumpAndSettle();

    expect(find.text("Account deletion request copied."), findsOneWidget);
  });

  testWidgets("account deletion dialog opens configured deletion URL",
      (tester) async {
    Uri? launchedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          accountDeletionUrl: "https://support.keepeyeonball.com/delete",
          accountDeletionLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.text("Request Account Deletion"));
    await tester.pumpAndSettle();

    expect(find.text("Open Deletion Page"), findsOneWidget);
    expect(
      find.text("https://support.keepeyeonball.com/delete"),
      findsOneWidget,
    );

    await tester.tap(find.text("Open Deletion Page"));
    await tester.pumpAndSettle();

    expect(
      launchedUri,
      Uri.parse("https://support.keepeyeonball.com/delete"),
    );
    expect(find.text("Account deletion page opened."), findsOneWidget);
  });

  testWidgets("privacy and support actions are available before login",
      (tester) async {
    final launchedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          privacyPolicyUrl: "https://support.keepeyeonball.com/privacy",
          supportUrl: "https://support.keepeyeonball.com/support",
          storeUrlLauncher: (uri) async {
            launchedUris.add(uri);
            return true;
          },
        ),
      ),
    );

    await tester.tap(find.text("Privacy Policy"));
    await tester.pumpAndSettle();

    expect(
      launchedUris,
      contains(Uri.parse("https://support.keepeyeonball.com/privacy")),
    );
    expect(find.text("Privacy policy opened."), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Support"));
    await tester.pumpAndSettle();

    expect(
      launchedUris,
      contains(Uri.parse("https://support.keepeyeonball.com/support")),
    );
    expect(find.text("Support page opened."), findsOneWidget);
  });

  testWidgets("privacy action shows local policy text when URL is unset",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    await tester.tap(find.text("Privacy Policy"));
    await tester.pumpAndSettle();

    expect(find.text("Privacy Policy"), findsWidgets);
    expect(find.textContaining("Auth0 login identity"), findsOneWidget);
    expect(find.textContaining("HYDRACAM_PRIVACY_POLICY_URL"), findsOneWidget);
  });
}
