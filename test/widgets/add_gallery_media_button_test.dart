import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/widgets/add_gallery_media_button.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("button label fits narrow desktop panes", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(220, 160));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            child: AddGalleryMediaButton(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
