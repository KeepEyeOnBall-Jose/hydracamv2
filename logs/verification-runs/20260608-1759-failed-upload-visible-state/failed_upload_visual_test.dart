import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/widgets/media_list_widget.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("failed upload media list visual proof", (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 300));
    final tempDir =
        Directory.systemTemp.createTempSync("hydracam_failed_upload_visual");
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final failedPath = File("${tempDir.path}/failed.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final pendingPath = File("${tempDir.path}/pending.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 17, 45);

    final failedVideo = CapturedVideo(
      videoPath: failedPath.path,
      slaveDeviceId: "failed-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      uploadStartTime: capturedAt.add(const Duration(seconds: 7)),
    );
    final pendingVideo = CapturedVideo(
      videoPath: pendingPath.path,
      slaveDeviceId: "pending-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaListWidget(
            photos: const [],
            videos: [failedVideo, pendingVideo],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile("screenshots/failed_upload_visible_state.png"),
    );
  });
}
