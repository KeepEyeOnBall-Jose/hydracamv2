import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/automation_standby_screen.dart";

void main() {
  testWidgets("standby screen renders visible status instead of a blank body",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AutomationStandbyScreen(),
      ),
    );

    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    expect(find.text("Automation standby"), findsOneWidget);
    expect(find.text("Waiting for role assignment"), findsOneWidget);
  });
}
