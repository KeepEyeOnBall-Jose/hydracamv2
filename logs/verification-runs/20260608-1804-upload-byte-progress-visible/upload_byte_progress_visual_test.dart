import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/widgets/media_list_widget.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("upload byte progress visual proof", (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 280));
    final tempDir =
        Directory.systemTemp.createTempSync("hydracam_byte_progress_visual");
    addTearDown(() async {
      UploaderService().reset();
      await tester.binding.setSurfaceSize(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final videoPath = File("${tempDir.path}/uploading.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 18, 4);
    final video = CapturedVideo(
      videoPath: videoPath.path,
      slaveDeviceId: "uploading-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      uploadStartTime: capturedAt.add(const Duration(seconds: 7)),
    );

    UploaderService().currentlyUploadingNotifier.value = video;
    UploaderService().uploadProgressNotifier.value = 0.5;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaListWidget(
            photos: const [],
            videos: [video],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile("screenshots/upload_byte_progress_visible.png"),
    );
  });
}
