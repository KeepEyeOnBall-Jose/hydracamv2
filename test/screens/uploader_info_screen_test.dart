import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/screens/uploader_info_screen.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:package_info_plus/package_info_plus.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _UploaderInfoPathProvider pathProvider = _UploaderInfoPathProvider();
  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    UploaderService().reset();
    tempDir = Directory.systemTemp.createTempSync("uploader_info_screen_test");
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    UploaderService().reset();
    HydraCamApiService.resetHttpClient();
    M2MAuthService.clearTokenOverrideForTests();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  testWidgets("cancel action clears the current upload row", (tester) async {
    SessionManager.instance.startSession(
      "uploader-info-session-guid",
      "uploader-info-session",
      deviceType: "Slave",
    );

    final videoFile = File("${tempDir.path}/current-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final video = CapturedVideo(
      videoPath: videoFile.path,
      slaveDeviceId: "uploader-info-device",
      startRecordingDate: DateTime(2026, 6, 8, 19, 40),
      endRecordingDate: DateTime(2026, 6, 8, 19, 40, 5),
      receivedDate: DateTime(2026, 6, 8, 19, 40, 6),
    );

    SessionManager.instance.currentSession?.addVideo(video);
    UploaderService().currentlyUploadingNotifier.value = video;

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.byTooltip("Cancel upload"), findsOneWidget);

    await _pressCancelUploadButton(
      tester,
      isComplete: () =>
          UploaderService().currentlyUploadingNotifier.value == null,
    );

    expect(UploaderService().isUploading, isFalse);
    expect(UploaderService().currentlyUploadingNotifier.value, isNull);
  });

  testWidgets("queued cancel action refreshes row as retryable cancellation",
      (tester) async {
    SessionManager.instance.startSession(
      "uploader-info-queued-session-guid",
      "uploader-info-queued-session",
      deviceType: "Slave",
    );

    final videoFile = File("${tempDir.path}/queued-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final video = CapturedVideo(
      videoPath: videoFile.path,
      slaveDeviceId: "uploader-info-queued-device",
      startRecordingDate: DateTime(2026, 6, 17, 15, 25),
      endRecordingDate: DateTime(2026, 6, 17, 15, 25, 5),
      receivedDate: DateTime(2026, 6, 17, 15, 25, 6),
    );

    SessionManager.instance.currentSession?.addVideo(video);
    await UploaderService().addMediaToQueue(video);

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Pending upload"), findsOneWidget);
    expect(find.byTooltip("Cancel upload"), findsOneWidget);

    await _pressCancelUploadButton(
      tester,
      isComplete: () => video.uploadFailureReason == "Upload cancelled.",
    );

    expect(find.text("Upload cancelled."), findsOneWidget);
    expect(find.byTooltip("Retry upload"), findsOneWidget);
    expect(find.byTooltip("Cancel upload"), findsNothing);
  });

  testWidgets("summary shows pending queue and current upload", (tester) async {
    SessionManager.instance.startSession(
      "uploader-info-summary-guid",
      "uploader-info-summary",
      deviceType: "Master",
    );

    final currentFile = File("${tempDir.path}/current-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final queuedFile = File("${tempDir.path}/queued-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final currentVideo = CapturedVideo(
      videoPath: currentFile.path,
      slaveDeviceId: "summary-current-device",
      startRecordingDate: DateTime(2026, 6, 17, 16),
      endRecordingDate: DateTime(2026, 6, 17, 16, 0, 4),
      receivedDate: DateTime(2026, 6, 17, 16, 0, 5),
    );
    final queuedVideo = CapturedVideo(
      videoPath: queuedFile.path,
      slaveDeviceId: "summary-queued-device",
      startRecordingDate: DateTime(2026, 6, 17, 16, 1),
      endRecordingDate: DateTime(2026, 6, 17, 16, 1, 4),
      receivedDate: DateTime(2026, 6, 17, 16, 1, 5),
    );

    SessionManager.instance.currentSession?.addVideo(currentVideo);
    SessionManager.instance.currentSession?.addVideo(queuedVideo);
    UploaderService().currentlyUploadingNotifier.value = currentVideo;
    await UploaderService().addMediaToQueue(queuedVideo);

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Queue: 1 pending"), findsOneWidget);
    expect(find.text("Current upload: current-upload.mp4"), findsOneWidget);
  });

  testWidgets("summary avoids zero ETA while current upload is active",
      (tester) async {
    SessionManager.instance.startSession(
      "uploader-info-active-eta-guid",
      "uploader-info-active-eta",
      deviceType: "Master",
    );

    final currentFile = File("${tempDir.path}/current-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final currentVideo = CapturedVideo(
      videoPath: currentFile.path,
      slaveDeviceId: "summary-current-device",
      startRecordingDate: DateTime(2026, 6, 18, 17, 28),
      endRecordingDate: DateTime(2026, 6, 18, 17, 28, 4),
      receivedDate: DateTime(2026, 6, 18, 17, 28, 5),
    );

    SessionManager.instance.currentSession?.addVideo(currentVideo);
    UploaderService().currentlyUploadingNotifier.value = currentVideo;
    UploaderService().estimatedTimeNotifier.value = Duration.zero;

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Queue: 0 pending"), findsOneWidget);
    expect(find.text("Current upload: current-upload.mp4"), findsOneWidget);
    expect(find.text("Estimated remaining: 0s"), findsNothing);
    expect(find.text("Estimated remaining: calculating"), findsOneWidget);
  });

  testWidgets("summary shows zero ETA when idle", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Current upload: none"), findsOneWidget);
    expect(find.text("Estimated remaining: 0s"), findsOneWidget);
  });

  testWidgets("start uploads action drains the pending queue", (tester) async {
    M2MAuthService.overrideTokenForTests("test-token");
    PackageInfo.setMockInitialValues(
      appName: "HydraCam",
      packageName: "com.vectorblanco.hydracam.dev",
      version: "2.3.4",
      buildNumber: "567",
      buildSignature: "",
    );
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );
    SessionManager.instance.startSession(
      "uploader-info-start-guid",
      "uploader-info-start",
      deviceType: "Master",
    );

    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "summary-upload-device",
      captureDate: DateTime(2026, 6, 17, 16, 30),
      receivedDate: DateTime(2026, 6, 17, 16, 30, 1),
    );
    SessionManager.instance.currentSession?.addPhoto(photo);
    await UploaderService().addMediaToQueue(photo);

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.text("Queue: 1 pending"), findsOneWidget);

    final startUploadsButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, "Start Uploads"),
    );
    await tester.runAsync(() async {
      final onPressed = startUploadsButton.onPressed;
      if (onPressed != null) {
        final result = (onPressed as dynamic)();
        if (result is Future<void>) {
          await result;
        }
      }
    });
    await tester.pump();

    expect(photo.isUploaded, isTrue);
    expect(find.text("Queue: 0 pending"), findsOneWidget);
  });
}

List<int> _validJpegBytes() {
  return [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
}

Future<void> _pressCancelUploadButton(
  WidgetTester tester, {
  required bool Function() isComplete,
}) async {
  final cancelButtonFinder = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == "Cancel upload",
  );
  expect(cancelButtonFinder, findsOneWidget);
  final cancelButton = tester.widget<IconButton>(cancelButtonFinder);

  await tester.runAsync(() async {
    final onPressed = cancelButton.onPressed;
    if (onPressed != null) {
      final result = (onPressed as dynamic)();
      if (result is Future<void>) {
        await result;
      }
    }
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!isComplete() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pump();

  expect(isComplete(), isTrue);
}

class _UploaderInfoPathProvider extends PathProviderPlatform {
  final Directory documentsDir =
      Directory.systemTemp.createTempSync("uploader_info_screen_docs");

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}
