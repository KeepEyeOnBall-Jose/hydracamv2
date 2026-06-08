import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/hydra_cam_app_bar.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("hides action menu during tiny startup layouts", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1, 80));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: HydraCamAppBar(
            title: "HydraCam - Slave Device",
            onBack: () {},
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
