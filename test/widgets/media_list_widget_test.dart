import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/widgets/media_list_widget.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("hydracam_media_list_test");
  });

  tearDown(() {
    UploaderService().reset();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets("media list distinguishes failed uploads from pending uploads",
      (tester) async {
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
          body: SizedBox(
            height: 240,
            child: MediaListWidget(
              photos: const [],
              videos: [failedVideo, pendingVideo],
            ),
          ),
        ),
      ),
    );

    expect(find.text("Upload failed"), findsOneWidget);
    expect(find.text("Pending upload"), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text("Pending"), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload), findsNothing);
  });

  testWidgets("upload state is presented as a labeled status indicator",
      (tester) async {
    final pendingPath = File("${tempDir.path}/pending-status.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final uploadedPath = File("${tempDir.path}/uploaded-status.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 18, 1);

    final pendingVideo = CapturedVideo(
      videoPath: pendingPath.path,
      slaveDeviceId: "pending-status-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
    );
    final uploadedVideo = CapturedVideo(
      videoPath: uploadedPath.path,
      slaveDeviceId: "uploaded-status-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      isUploaded: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: MediaListWidget(
              photos: const [],
              videos: [pendingVideo, uploadedVideo],
            ),
          ),
        ),
      ),
    );

    expect(find.text("Pending"), findsOneWidget);
    expect(find.text("Uploaded"), findsWidgets);
    expect(
      find.bySemanticsLabel("Upload status: Pending upload"),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel("Upload status: Uploaded"), findsOneWidget);
    expect(find.byTooltip("Pending upload"), findsNothing);
    expect(find.byTooltip("Uploaded"), findsNothing);
    expect(find.byIcon(Icons.cloud_upload), findsNothing);
  });

  testWidgets("current upload progress includes uploaded and total bytes",
      (tester) async {
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
          body: SizedBox(
            height: 180,
            child: MediaListWidget(
              photos: const [],
              videos: [video],
            ),
          ),
        ),
      ),
    );

    expect(find.text("50%"), findsOneWidget);
    expect(find.text("2 B / 4 B"), findsOneWidget);
  });

  testWidgets("current upload progress includes estimated time remaining",
      (tester) async {
    final videoPath = File("${tempDir.path}/uploading-time.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 18, 30);
    final uploadStartedAt = capturedAt.add(const Duration(seconds: 7));
    final video = CapturedVideo(
      videoPath: videoPath.path,
      slaveDeviceId: "uploading-time-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      uploadStartTime: uploadStartedAt,
    );

    UploaderService().currentlyUploadingNotifier.value = video;
    UploaderService().uploadProgressNotifier.value = 0.5;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: MediaListWidget(
              photos: const [],
              videos: [video],
              now: () => uploadStartedAt.add(const Duration(seconds: 4)),
            ),
          ),
        ),
      ),
    );

    expect(find.text("About 4s left"), findsOneWidget);
  });

  testWidgets("upload actions distinguish retry from queue upload",
      (tester) async {
    final failedPath = File("${tempDir.path}/failed-action.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final pendingPath = File("${tempDir.path}/pending-action.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 18, 7);

    final failedVideo = CapturedVideo(
      videoPath: failedPath.path,
      slaveDeviceId: "failed-action-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      uploadStartTime: capturedAt.add(const Duration(seconds: 7)),
    );
    final pendingVideo = CapturedVideo(
      videoPath: pendingPath.path,
      slaveDeviceId: "pending-action-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
    );

    final requeued = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: MediaListWidget(
              photos: const [],
              videos: [failedVideo, pendingVideo],
              onRetryVideoUpload: (video) => requeued.add(video.slaveDeviceId),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip("Retry upload"), findsOneWidget);
    expect(find.byTooltip("Queue upload"), findsOneWidget);

    await tester.tap(find.byTooltip("Retry upload"));
    await tester.tap(find.byTooltip("Queue upload"));

    expect(requeued, ["failed-action-device", "pending-action-device"]);
  });

  testWidgets("missing local media rows suppress upload actions",
      (tester) async {
    final capturedAt = DateTime(2026, 6, 17, 10, 22);
    final missingPhoto = CapturedPhoto(
      photoPath: "${tempDir.path}/missing-photo.jpg",
      slaveDeviceId: "missing-photo-device",
      captureDate: capturedAt,
      receivedDate: capturedAt.add(const Duration(seconds: 1)),
    );
    final missingVideo = CapturedVideo(
      videoPath: "${tempDir.path}/missing-video.mp4",
      slaveDeviceId: "missing-video-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
    );

    final requeued = <String>[];
    final cancelled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: MediaListWidget(
              photos: [missingPhoto],
              videos: [missingVideo],
              onRetryPhotoUpload: (photo) => requeued.add(photo.slaveDeviceId),
              onRetryVideoUpload: (video) => requeued.add(video.slaveDeviceId),
              onCancelPhotoUpload: (photo) =>
                  cancelled.add(photo.slaveDeviceId),
              onCancelVideoUpload: (video) =>
                  cancelled.add(video.slaveDeviceId),
            ),
          ),
        ),
      ),
    );

    expect(find.text("Local file missing"), findsNWidgets(2));
    expect(find.bySemanticsLabel("Upload status: Local file missing"),
        findsNWidgets(2));
    expect(find.byTooltip("Queue upload"), findsNothing);
    expect(find.byTooltip("Retry upload"), findsNothing);
    expect(find.byTooltip("Cancel upload"), findsNothing);
    expect(requeued, isEmpty);
    expect(cancelled, isEmpty);
  });

  testWidgets("pending upload can be cancelled from the media row",
      (tester) async {
    final pendingPath = File("${tempDir.path}/pending-cancel.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 18, 43);

    final pendingVideo = CapturedVideo(
      videoPath: pendingPath.path,
      slaveDeviceId: "pending-cancel-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
    );

    final cancelled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: MediaListWidget(
              photos: const [],
              videos: [pendingVideo],
              onCancelVideoUpload: (video) {
                cancelled.add(video.slaveDeviceId);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip("Cancel upload"), findsOneWidget);

    await tester.tap(find.byTooltip("Cancel upload"));

    expect(cancelled, ["pending-cancel-device"]);
  });

  testWidgets("current upload can be cancelled from the media row",
      (tester) async {
    final uploadingPath = File("${tempDir.path}/current-cancel.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedAt = DateTime(2026, 6, 8, 19, 35);

    final uploadingVideo = CapturedVideo(
      videoPath: uploadingPath.path,
      slaveDeviceId: "current-cancel-device",
      startRecordingDate: capturedAt,
      endRecordingDate: capturedAt.add(const Duration(seconds: 5)),
      receivedDate: capturedAt.add(const Duration(seconds: 6)),
      uploadStartTime: capturedAt.add(const Duration(seconds: 7)),
    );

    UploaderService().currentlyUploadingNotifier.value = uploadingVideo;

    final cancelled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: MediaListWidget(
              photos: const [],
              videos: [uploadingVideo],
              onCancelVideoUpload: (video) {
                cancelled.add(video.slaveDeviceId);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip("Cancel upload"), findsOneWidget);

    await tester.tap(find.byTooltip("Cancel upload"));

    expect(cancelled, ["current-cancel-device"]);
  });
}
