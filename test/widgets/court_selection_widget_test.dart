import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/court_selection_widget.dart";

void main() {
  const groupedCourts = {
    "Center A": [
      {"name": "Court A", "guid": "court-a-guid"},
      {"name": "Court B", "guid": "court-b-guid"},
    ],
    "Center B": [
      {"name": "Court A", "guid": "center-b-court-a-guid"},
    ],
  };

  Future<void> pumpSelector(
    WidgetTester tester,
    List<CourtSelection?> selections,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: CourtSelectionWidget(
              groupedCourts: groupedCourts,
              onCourtSelected: selections.add,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectCenter(WidgetTester tester, String center) async {
    await tester.tap(find.byKey(const ValueKey("sportsCenterDropdown")));
    await tester.pumpAndSettle();
    await tester.tap(find.text(center).last);
    await tester.pumpAndSettle();
  }

  testWidgets("uses a visible center-first court selection flow",
      (tester) async {
    final selections = <CourtSelection?>[];

    await pumpSelector(tester, selections);

    expect(find.text("Capture location"), findsOneWidget);
    expect(find.text("Sports center"), findsOneWidget);
    expect(find.byKey(const ValueKey("court-court-a-guid")), findsNothing);

    await selectCenter(tester, "Center A");

    expect(selections, [null]);
    expect(find.text("Search courts"), findsOneWidget);
    expect(find.byKey(const ValueKey("court-court-a-guid")), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("court-court-a-guid")));
    await tester.pumpAndSettle();

    expect(
      selections.last,
      const CourtSelection(
        sportsCenterName: "Center A",
        courtName: "Court A",
        courtGuid: "court-a-guid",
      ),
    );
    expect(find.text("Center A · Court A"), findsOneWidget);
  });

  testWidgets("searching does not clear the selected court", (tester) async {
    final selections = <CourtSelection?>[];

    await pumpSelector(tester, selections);
    await selectCenter(tester, "Center A");
    await tester.tap(find.byKey(const ValueKey("court-court-a-guid")));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey("courtSearchField")), "B");
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selections.whereType<CourtSelection>().single.courtGuid,
        "court-a-guid");
    expect(find.text("Center A · Court A"), findsOneWidget);
    expect(find.byKey(const ValueKey("court-court-b-guid")), findsOneWidget);
  });

  testWidgets("changing centers clears the parent selection", (tester) async {
    final selections = <CourtSelection?>[];

    await pumpSelector(tester, selections);
    await selectCenter(tester, "Center A");
    await tester.tap(find.byKey(const ValueKey("court-court-a-guid")));
    await tester.pumpAndSettle();

    await selectCenter(tester, "Center B");

    expect(selections.last, isNull);
    expect(find.text("Center A · Court A"), findsNothing);
    expect(
      find.byKey(const ValueKey("court-center-b-court-a-guid")),
      findsOneWidget,
    );
  });

  testWidgets("duplicate court names select by guid", (tester) async {
    final selections = <CourtSelection?>[];

    await pumpSelector(tester, selections);
    await selectCenter(tester, "Center B");
    await tester.tap(find.byKey(const ValueKey("court-center-b-court-a-guid")));
    await tester.pumpAndSettle();

    expect(
      selections.last,
      const CourtSelection(
        sportsCenterName: "Center B",
        courtName: "Court A",
        courtGuid: "center-b-court-a-guid",
      ),
    );
  });

  testWidgets("clear action notifies parent with null", (tester) async {
    final selections = <CourtSelection?>[];

    await pumpSelector(tester, selections);
    await selectCenter(tester, "Center A");
    await tester.tap(find.byKey(const ValueKey("court-court-b-guid")));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("clearCourtSelectionButton")));
    await tester.pumpAndSettle();

    expect(selections.last, isNull);
    expect(find.text("Center A · Court B"), findsNothing);
  });
}
