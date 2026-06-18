import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/animated_countdown_timer.dart";

void main() {
  testWidgets("zero duration completes without invalid progress",
      (tester) async {
    var completionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedCountdownTimer(
          duration: 0,
          onComplete: () {
            completionCount += 1;
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(completionCount, 1);
    expect(find.text("Go!"), findsOneWidget);
  });

  testWidgets("overdue negative duration completes without invalid progress",
      (tester) async {
    var completionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedCountdownTimer(
          duration: -100,
          onComplete: () {
            completionCount += 1;
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(completionCount, 1);
    expect(find.text("Go!"), findsOneWidget);
  });
}
