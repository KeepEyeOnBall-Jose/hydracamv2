import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/court_selection_widget.dart";

void main() {
  testWidgets("searching after court selection keeps dropdown value valid",
      (tester) async {
    final selections = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtSelectionWidget(
            groupedCourts: const {
              "Center A": [
                {"name": "Court A", "guid": "court-a-guid"},
                {"name": "Court B", "guid": "court-b-guid"},
              ],
            },
            onCourtSelected: (name, guid) {
              selections.add("$name:$guid");
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Center A").last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Court A").last);
    await tester.pumpAndSettle();

    expect(selections, ["Court A:court-a-guid"]);

    await tester.enterText(find.byType(TextField), "Court B");
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selections, ["Court A:court-a-guid"]);
    expect(find.text("Court B"), findsOneWidget);
  });
}
