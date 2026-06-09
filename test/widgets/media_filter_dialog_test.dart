import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/media_filter_dialog.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("browse all returns unconstrained media filters", (tester) async {
    MediaFilters? selectedFilters;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  selectedFilters = await showDialog<MediaFilters>(
                    context: context,
                    builder: (_) => const MediaFilterDialog(),
                  );
                },
                child: const Text("Open filters"),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text("Open filters"));
    await tester.pumpAndSettle();

    expect(find.text("Browse All"), findsOneWidget);
    expect(find.text("Apply"), findsOneWidget);

    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();

    expect(selectedFilters, isNotNull);
    expect(selectedFilters?.isPhoto, isTrue);
    expect(selectedFilters?.startDate, isNull);
    expect(selectedFilters?.endDate, isNull);
    expect(selectedFilters?.minDuration, isNull);
  });
}
