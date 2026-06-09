import "dart:async";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:package_info_plus/package_info_plus.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _TestPathProviderPlatform pathProvider = _TestPathProviderPlatform();
  late UploaderService uploaderService;
  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    M2MAuthService.overrideTokenForTests("test-token");
    PackageInfo.setMockInitialValues(
      appName: "HydraCam",
      packageName: "com.vectorblanco.hydracam.dev",
      version: "2.3.4",
      buildNumber: "567",
      buildSignature: "",
    );
    uploaderService = UploaderService();
    uploaderService.reset();
    LogService.instance.clearLogs();
    tempDir = Directory.systemTemp.createTempSync("hydracam_uploader_test");
    SessionManager.instance.startSession(
      "uploader-test-guid",
      "uploader-test-session",
      deviceType: "Master",
    );
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    UploaderService.resetNowForTests();
    uploaderService.reset();
    HydraCamApiService.resetHttpClient();
    LogService.instance.clearLogs();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test("reset clears stale queue, current upload state, and progress",
      () async {
    final photoFile = File("${tempDir.path}/photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "old-session-device",
      captureDate: DateTime(2026, 6, 8, 17, 30),
      receivedDate: DateTime(2026, 6, 8, 17, 31),
    );

    await uploaderService.addMediaToQueue(photo);
    uploaderService.currentlyUploadingNotifier.value = photo;
    uploaderService.estimatedTimeNotifier.value = const Duration(seconds: 42);
    uploaderService.uploadProgressNotifier.value = 0.73;

    expect(uploaderService.queueLength, 1);

    uploaderService.reset();

    expect(uploaderService.queueLength, 0);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
    expect(uploaderService.estimatedTimeNotifier.value, Duration.zero);
    expect(uploaderService.uploadProgressNotifier.value, 0.0);
  });

  test("addMediaToQueue can be awaited through settings evaluation", () async {
    final photoFile = File("${tempDir.path}/awaitable-enqueue.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "awaitable-device",
      captureDate: DateTime(2026, 6, 9, 2, 23),
      receivedDate: DateTime(2026, 6, 9, 2, 23, 1),
    );

    await uploaderService.addMediaToQueue(photo);

    expect(uploaderService.queueLength, 1);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(
        "Auto-upload is disabled. Media added to queue but not uploaded.",
      ),
    );
  });

  test("startUploadingManually can be awaited until the queue drains", () async {
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    final firstFile = File("${tempDir.path}/await-manual-first.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final secondFile = File("${tempDir.path}/await-manual-second.jpg")
      ..writeAsBytesSync([5, 6, 7, 8]);
    final firstPhoto = CapturedPhoto(
      photoPath: firstFile.path,
      slaveDeviceId: "await-manual-first",
      captureDate: DateTime(2026, 6, 9, 2, 45),
      receivedDate: DateTime(2026, 6, 9, 2, 45, 1),
    );
    final secondPhoto = CapturedPhoto(
      photoPath: secondFile.path,
      slaveDeviceId: "await-manual-second",
      captureDate: DateTime(2026, 6, 9, 2, 45, 2),
      receivedDate: DateTime(2026, 6, 9, 2, 45, 3),
    );

    await uploaderService.addMediaToQueue(firstPhoto);
    await uploaderService.addMediaToQueue(secondPhoto);

    await uploaderService.startUploadingManually();

    expect(firstPhoto.isUploaded, isTrue);
    expect(secondPhoto.isUploaded, isTrue);
    expect(uploaderService.queueLength, 0);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
  });

  test("addMediaToQueue refuses media when session is not backend-created",
      () async {
    await SessionManager.instance.endSession();
    SessionManager.instance.startSession(
      "diagnostic-session-guid",
      "diagnostic-session",
      deviceType: "Master",
      backendCreated: false,
    );
    final photoFile = File("${tempDir.path}/diagnostic-session.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "diagnostic-device",
      captureDate: DateTime(2026, 6, 9, 3, 0),
      receivedDate: DateTime(2026, 6, 9, 3, 0, 1),
    );

    await uploaderService.addMediaToQueue(photo);

    expect(uploaderService.queueLength, 0);
    expect(photo.isUploaded, isFalse);
    expect(photo.uploadFailureReason, contains("not backend-created"));
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(contains("session is not backend-created")),
    );
  });

  test("cancelQueuedMedia removes a pending item without touching others",
      () async {
    final firstFile = File("${tempDir.path}/first.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final secondFile = File("${tempDir.path}/second.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final firstPhoto = CapturedPhoto(
      photoPath: firstFile.path,
      slaveDeviceId: "first-device",
      captureDate: DateTime(2026, 6, 8, 18, 43),
      receivedDate: DateTime(2026, 6, 8, 18, 44),
    );
    final secondPhoto = CapturedPhoto(
      photoPath: secondFile.path,
      slaveDeviceId: "second-device",
      captureDate: DateTime(2026, 6, 8, 18, 45),
      receivedDate: DateTime(2026, 6, 8, 18, 46),
    );

    await uploaderService.addMediaToQueue(firstPhoto);
    await uploaderService.addMediaToQueue(secondPhoto);

    expect(uploaderService.queueLength, 2);
    expect(uploaderService.cancelQueuedMedia(firstPhoto), isTrue);
    expect(uploaderService.queueLength, 1);
    expect(uploaderService.cancelQueuedMedia(firstPhoto), isFalse);
    expect(uploaderService.queueLength, 1);
  });

  test("addMediaToQueue ignores retry for media already uploading", () async {
    final photoFile = File("${tempDir.path}/currently-uploading.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "uploading-device",
      captureDate: DateTime(2026, 6, 8, 21, 32),
      receivedDate: DateTime(2026, 6, 8, 21, 32, 1),
    );

    uploaderService.currentlyUploadingNotifier.value = photo;

    await uploaderService.addMediaToQueue(photo);

    expect(uploaderService.queueLength, 0);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Media already uploading: ${photo.mediaPath}"),
    );
  });

  test("estimateTotalTimeRemaining uses completed upload samples", () async {
    var now = DateTime.utc(2026, 6, 8, 21, 36);
    UploaderService.configureNowForTests(() => now);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        now = now.add(const Duration(seconds: 5));
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    SessionManager.instance.startSession(
      "estimate-session-guid",
      "estimate-session",
      deviceType: "Master",
    );
    final completedFile = File("${tempDir.path}/completed-estimate.jpg")
      ..writeAsBytesSync(List<int>.filled(100, 1));
    final pendingFile = File("${tempDir.path}/pending-estimate.jpg")
      ..writeAsBytesSync(List<int>.filled(200, 1));
    final completedPhoto = CapturedPhoto(
      photoPath: completedFile.path,
      slaveDeviceId: "estimate-completed",
      captureDate: now,
      receivedDate: now,
    );
    final pendingPhoto = CapturedPhoto(
      photoPath: pendingFile.path,
      slaveDeviceId: "estimate-pending",
      captureDate: now,
      receivedDate: now,
    );

    await uploaderService.addMediaToQueue(completedPhoto);
    await uploaderService.startUploadingManually();

    await uploaderService.addMediaToQueue(pendingPhoto);

    expect(uploaderService.queueLength, 1);
    expect(
      uploaderService.estimateTotalTimeRemaining(),
      const Duration(seconds: 10),
    );
    expect(
      uploaderService.estimatedTimeNotifier.value,
      const Duration(seconds: 10),
    );
  });

  test("estimateTotalTimeRemaining keeps sub-second upload samples", () async {
    var now = DateTime.utc(2026, 6, 9, 1, 38);
    UploaderService.configureNowForTests(() => now);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        now = now.add(const Duration(milliseconds: 500));
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    SessionManager.instance.startSession(
      "subsecond-estimate-guid",
      "subsecond-estimate",
      deviceType: "Master",
    );
    final completedFile = File("${tempDir.path}/subsecond-completed.jpg")
      ..writeAsBytesSync(List<int>.filled(100, 1));
    final pendingFile = File("${tempDir.path}/subsecond-pending.jpg")
      ..writeAsBytesSync(List<int>.filled(200, 1));
    final completedPhoto = CapturedPhoto(
      photoPath: completedFile.path,
      slaveDeviceId: "subsecond-completed",
      captureDate: now,
      receivedDate: now,
    );
    final pendingPhoto = CapturedPhoto(
      photoPath: pendingFile.path,
      slaveDeviceId: "subsecond-pending",
      captureDate: now,
      receivedDate: now,
    );

    await uploaderService.addMediaToQueue(completedPhoto);
    await uploaderService.startUploadingManually();

    await uploaderService.addMediaToQueue(pendingPhoto);

    expect(
      uploaderService.estimateTotalTimeRemaining(),
      const Duration(seconds: 1),
    );
  });

  test("reset ignores stale in-flight upload completion", () async {
    final releaseUpload = Completer<void>();
    final requestStarted = Completer<void>();
    final requestFinished = Completer<void>();
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        await releaseUpload.future;
        await bodyStream.drain<void>();
        if (!requestFinished.isCompleted) {
          requestFinished.complete();
        }
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    SessionManager.instance.startSession(
      "old-session-guid",
      "old-session",
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/inflight.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "old-session-device",
      captureDate: DateTime(2026, 6, 8, 19, 18),
      receivedDate: DateTime(2026, 6, 8, 19, 18, 1),
    );

    await uploaderService.addMediaToQueue(photo);
    final uploadFuture = uploaderService.startUploadingManually();
    await requestStarted.future.timeout(const Duration(seconds: 1));

    uploaderService.reset();
    SessionManager.instance.startSession(
      "new-session-guid",
      "new-session",
      deviceType: "Master",
    );

    releaseUpload.complete();
    await requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;

    expect(SessionManager.instance.sessionGuid, "new-session-guid");
    expect(SessionManager.instance.currentSession?.capturedPhotos, isEmpty);
    expect(photo.isUploaded, isFalse);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
  });

  test("cancelCurrentUpload clears active upload and ignores late completion",
      () async {
    final releaseUpload = Completer<void>();
    final requestStarted = Completer<void>();
    final requestFinished = Completer<void>();
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        await releaseUpload.future;
        await bodyStream.drain<void>();
        if (!requestFinished.isCompleted) {
          requestFinished.complete();
        }
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    SessionManager.instance.startSession(
      "cancel-session-guid",
      "cancel-session",
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/cancel-inflight.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "cancel-device",
      captureDate: DateTime(2026, 6, 8, 19, 30),
      receivedDate: DateTime(2026, 6, 8, 19, 30, 1),
    );

    await uploaderService.addMediaToQueue(photo);
    final uploadFuture = uploaderService.startUploadingManually();
    await requestStarted.future.timeout(const Duration(seconds: 1));

    uploaderService.uploadProgressNotifier.value = 0.5;

    expect(uploaderService.cancelCurrentUpload(), isTrue);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
    expect(uploaderService.uploadProgressNotifier.value, 0.0);

    releaseUpload.complete();
    await requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;

    expect(photo.isUploaded, isFalse);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
    expect(uploaderService.queueLength, 0);
  });

  test("cancelCurrentUpload closes the active HTTP client", () async {
    final client = _CloseTrackingClient();
    HydraCamApiService.configureHttpClient(client);

    SessionManager.instance.startSession(
      "cancel-http-session-guid",
      "cancel-http-session",
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/cancel-http.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "cancel-http-device",
      captureDate: DateTime(2026, 6, 8, 19, 45),
      receivedDate: DateTime(2026, 6, 8, 19, 45, 1),
    );

    await uploaderService.addMediaToQueue(photo);
    final uploadFuture = uploaderService.startUploadingManually();
    await client.requestStarted.future.timeout(const Duration(seconds: 1));

    expect(client.closeCount, 0);
    expect(uploaderService.cancelCurrentUpload(), isTrue);
    expect(client.closeCount, 1);

    await client.requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;

    expect(photo.isUploaded, isFalse);
    expect(uploaderService.isUploading, isFalse);
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  final Directory documentsDir =
      Directory.systemTemp.createTempSync("uploader_service_docs");

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

class _CloseTrackingClient extends http.BaseClient {
  final Completer<void> requestStarted = Completer<void>();
  final Completer<void> requestFinished = Completer<void>();
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requestStarted.isCompleted) {
      requestStarted.complete();
    }
    await request.finalize().drain<void>();
    if (!requestFinished.isCompleted) {
      requestFinished.complete();
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([<int>[]]),
      200,
    );
  }

  @override
  void close() {
    closeCount += 1;
    super.close();
  }
}
