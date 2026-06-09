import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/uploader_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("uploader reset progress visual proof", (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 220));
    addTearDown(() async {
      UploaderService().reset();
      await tester.binding.setSurfaceSize(null);
    });

    final uploaderService = UploaderService();
    uploaderService.uploadProgressNotifier.value = 0.73;
    uploaderService.reset();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: uploaderService.uploadProgressNotifier,
              builder: (context, progress, _) {
                return Text(
                  "Upload progress after reset: ${(progress * 100).round()}%",
                  style: const TextStyle(fontSize: 18),
                );
              },
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile("screenshots/uploader_reset_progress.png"),
    );
  });
}
