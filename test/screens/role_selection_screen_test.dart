import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/screens/role_selection_screen.dart";

void main() {
  testWidgets("role selection is an operational capture entry surface",
      (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(360, 640));

    await tester.pumpWidget(
      const MaterialApp(home: RoleSelectionScreen()),
    );
    await tester.pump();

    expect(find.text("HydraCam Capture"), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text("No active session"), findsOneWidget);
    expect(find.text("Local network required"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, "Master"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, "Slave"), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(ElevatedButton, "Master")).height,
      greaterThanOrEqualTo(56),
    );
    expect(
      tester.getSize(find.widgetWithText(ElevatedButton, "Slave")).height,
      greaterThanOrEqualTo(56),
    );
    final handledBack = await tester.binding.handlePopRoute();
    expect(handledBack, isTrue);
    await tester.pump();
    expect(find.text("HydraCam Capture"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
