import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/settings_screen.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  testWidgets("settings screen shows capture settings instead of camera quality",
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Capture Settings"), findsOneWidget);
    expect(find.text("Camera Lens"), findsOneWidget);
    expect(find.text("Video Profile"), findsOneWidget);
    expect(find.text("1080p at 30 fps"), findsOneWidget);
    expect(find.text("Standard 1080p30"), findsNothing);
    expect(find.text("Auto back camera"), findsOneWidget);
    expect(find.textContaining("Target: 1080p at 30 fps"), findsOneWidget);
    expect(find.text("Camera Quality"), findsNothing);
  });
}
