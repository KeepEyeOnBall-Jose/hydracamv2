import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";
import "package:hydracam/widgets/hydracam_surface.dart";

void main() {
  testWidgets("surface uses the default operational surface tone",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HydraCamSurface(
            child: Text("Session status"),
          ),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(HydraCamSurface),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = decoratedBox.decoration as BoxDecoration;

    expect(find.text("Session status"), findsOneWidget);
    expect(decoration.color, AppTheme.surface);
    expect(decoration.border?.top.color, AppTheme.border);
  });

  testWidgets("danger status chip names the state and uses danger tone",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HydraCamStatusChip(
            status: HydraCamStatusTone.danger,
            icon: Icons.error,
            label: "Storage critical",
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.text("Storage critical"), findsOneWidget);

    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, AppTheme.dangerSurface);
    expect(chip.side?.color, AppTheme.danger);
  });

  testWidgets("badge always exposes a label with optional icon",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HydraCamBadge(
            icon: Icons.sync,
            label: "Bridge warm",
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.text("Bridge warm"), findsOneWidget);
  });

  testWidgets("badge uses danger styling only for explicit danger tone",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HydraCamBadge(label: "Connected"),
              HydraCamBadge(
                tone: HydraCamStatusTone.danger,
                label: "Disconnected",
              ),
            ],
          ),
        ),
      ),
    );

    final neutralBadge = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text("Connected"),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final dangerBadge = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text("Disconnected"),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );

    final neutralDecoration = neutralBadge.decoration as BoxDecoration;
    final dangerDecoration = dangerBadge.decoration as BoxDecoration;

    expect(neutralDecoration.color, isNot(AppTheme.dangerSurface));
    expect(neutralDecoration.border?.top.color, isNot(AppTheme.danger));
    expect(dangerDecoration.color, AppTheme.dangerSurface);
    expect(dangerDecoration.border?.top.color, AppTheme.danger);
  });

  testWidgets("toolbar lays out action buttons with readable disabled text",
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HydraCamToolbar(
            children: [
              HydraCamButton(
                icon: Icons.videocam,
                label: "Start",
                onPressed: () {},
              ),
              const HydraCamButton(
                icon: Icons.stop,
                label: "Stop",
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.text("Start"), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.text("Stop"), findsOneWidget);

    final disabledButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, "Stop"),
    );
    expect(disabledButton.enabled, isFalse);
  });
}
