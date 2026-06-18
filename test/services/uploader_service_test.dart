import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/settings_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:package_info_plus/package_info_plus.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

const List<int> _validJpegHeader = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const int _validJpegHeaderLength = 6;

List<int> _validJpegBytes({int length = _validJpegHeaderLength, int fill = 0}) {
  final paddingLength = length - _validJpegHeader.length;
  return <int>[
    ..._validJpegHeader,
    ...List<int>.filled(paddingLength, fill),
  ];
}

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
      ..writeAsBytesSync(_validJpegBytes());
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
      ..writeAsBytesSync(_validJpegBytes());
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

  test("startUploadingManually can be awaited until the queue drains",
      () async {
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
      ..writeAsBytesSync(_validJpegBytes(fill: 1));
    final secondFile = File("${tempDir.path}/await-manual-second.jpg")
      ..writeAsBytesSync(_validJpegBytes(fill: 2));
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

  test("addMediaToQueue refuses media when no service session is active",
      () async {
    await SessionManager.instance.endSession();
    final photoFile = File("${tempDir.path}/unattached-media.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "diagnostic-device",
      captureDate: DateTime(2026, 6, 18, 3),
      receivedDate: DateTime(2026, 6, 18, 3, 0, 1),
    );

    await uploaderService.addMediaToQueue(photo);

    expect(uploaderService.queueLength, 0);
    expect(photo.isUploaded, isFalse);
    expect(photo.uploadFailureReason, contains("no active service session"));
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains(contains("no active service session")),
    );
  });

  test("startUploadingManually marks missing queued file as failed", () async {
    SessionManager.instance.startCreatedSession(
      const HydraCamBackendSession(
        guid: "missing-file-session-guid",
        sessionId: "missing-file-session",
      ),
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/deleted-before-upload.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "deleted-file-device",
      captureDate: DateTime(2026, 6, 17, 15, 20),
      receivedDate: DateTime(2026, 6, 17, 15, 20, 1),
    );

    await SessionManager.instance.addPhoto(photo);
    await photoFile.delete();

    await uploaderService.startUploadingManually();

    expect(uploaderService.queueLength, 0);
    expect(uploaderService.isUploading, isFalse);
    expect(photo.isUploaded, isFalse);
    expect(photo.uploadFailureReason, contains("file does not exist"));

    final metadataFile = File(
      "${pathProvider.documentsDir.path}/session_missing-file-session-guid/metadata.json",
    );
    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    final photos = metadata["photos"] as List<dynamic>;
    expect(photos, hasLength(1));
    expect(
      photos.single,
      containsPair(
        "uploadFailureReason",
        "Upload failed: file does not exist on disk.",
      ),
    );
  });

  test(
      "debug session upload deletes local media even when user setting is false",
      () async {
    HydraCamApiService.configureHttpClient(MockClient((request) async {
      if (request.method == "POST") {
        return http.Response("{}", 200);
      }
      return http.Response("{}", 200);
    }));
    await SettingsService.setDeleteLocalAfterUpload(false);
    SessionManager.instance.startSession(
      "debug-service-session-guid",
      "debug-android-20260618T123456Z",
      deviceType: "Master",
      debugSession: true,
    );
    final photoFile = File("${tempDir.path}/debug-photo.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "debug-device",
      captureDate: DateTime(2026, 6, 18, 12, 35),
      receivedDate: DateTime(2026, 6, 18, 12, 35, 1),
    );

    await SessionManager.instance.addPhoto(photo);
    await uploaderService.startUploadingManually();

    expect(photo.isUploaded, isTrue);
    expect(photoFile.existsSync(), isFalse);
  });

  test("failed backend upload stores backend response detail on media",
      () async {
    SessionManager.instance.startCreatedSession(
      const HydraCamBackendSession(
        guid: "backend-failure-detail-guid",
        sessionId: "backend-failure-detail-session",
      ),
      deviceType: "Master",
    );
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              jsonEncode({
                "success": false,
                "message": "Rejected corrupt media",
              }),
            ),
          ]),
          200,
        );
      }),
    );
    final photoFile = File("${tempDir.path}/backend-failure-detail.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "backend-failure-device",
      captureDate: DateTime(2026, 6, 18, 16, 30),
      receivedDate: DateTime(2026, 6, 18, 16, 30, 1),
    );

    await SessionManager.instance.addPhoto(photo);
    await uploaderService.startUploadingManually();

    const expectedFailure =
        'Upload failed: HTTP 200 backend response reported failure - {"success":false,"message":"Rejected corrupt media"}';
    expect(photo.isUploaded, isFalse);
    expect(photo.uploadFailureReason, expectedFailure);
    expect(
      await _readPersistedPhotoFailureReason(
        documentsDir: pathProvider.documentsDir,
        sessionGuid: "backend-failure-detail-guid",
      ),
      expectedFailure,
    );
  });

  test("cancelQueuedMedia removes a pending item without touching others",
      () async {
    final firstFile = File("${tempDir.path}/first.jpg")
      ..writeAsBytesSync(_validJpegBytes(fill: 1));
    final secondFile = File("${tempDir.path}/second.jpg")
      ..writeAsBytesSync(_validJpegBytes(fill: 2));
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
    expect(await uploaderService.cancelQueuedMedia(firstPhoto), isTrue);
    expect(uploaderService.queueLength, 1);
    expect(firstPhoto.isUploaded, isFalse);
    expect(firstPhoto.uploadStartTime, isNotNull);
    expect(firstPhoto.uploadFailureReason, "Upload cancelled.");
    expect(secondPhoto.uploadFailureReason, isNull);
    expect(await uploaderService.cancelQueuedMedia(firstPhoto), isFalse);
    expect(uploaderService.queueLength, 1);
  });

  test("cancelQueuedMedia persists queued cancellation metadata", () async {
    SessionManager.instance.startCreatedSession(
      const HydraCamBackendSession(
        guid: "queued-cancel-metadata-guid",
        sessionId: "queued-cancel-metadata-session",
      ),
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/queued-cancel-metadata.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-cancel-metadata-device",
      captureDate: DateTime(2026, 6, 17, 15, 45),
      receivedDate: DateTime(2026, 6, 17, 15, 45, 1),
    );

    await SessionManager.instance.addPhoto(photo);

    expect(await uploaderService.cancelQueuedMedia(photo), isTrue);

    final failureReason = await _readPersistedPhotoFailureReason(
      documentsDir: pathProvider.documentsDir,
      sessionGuid: "queued-cancel-metadata-guid",
    );
    expect(failureReason, "Upload cancelled.");
  });

  test("addMediaToQueue ignores retry for media already uploading", () async {
    final photoFile = File("${tempDir.path}/currently-uploading.jpg")
      ..writeAsBytesSync(_validJpegBytes());
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
      ..writeAsBytesSync(_validJpegBytes(length: 100, fill: 1));
    final pendingFile = File("${tempDir.path}/pending-estimate.jpg")
      ..writeAsBytesSync(_validJpegBytes(length: 200, fill: 1));
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
      ..writeAsBytesSync(_validJpegBytes(length: 100, fill: 1));
    final pendingFile = File("${tempDir.path}/subsecond-pending.jpg")
      ..writeAsBytesSync(_validJpegBytes(length: 200, fill: 1));
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
      ..writeAsBytesSync(_validJpegBytes());
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
      ..writeAsBytesSync(_validJpegBytes());
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

    expect(await uploaderService.cancelCurrentUpload(), isTrue);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
    expect(uploaderService.uploadProgressNotifier.value, 0.0);
    expect(photo.uploadFailureReason, "Upload cancelled.");

    releaseUpload.complete();
    await requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;

    expect(photo.isUploaded, isFalse);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);
    expect(uploaderService.queueLength, 0);
  });

  test("cancelCurrentUpload persists active cancellation metadata", () async {
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

    SessionManager.instance.startCreatedSession(
      const HydraCamBackendSession(
        guid: "active-cancel-metadata-guid",
        sessionId: "active-cancel-metadata-session",
      ),
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/active-cancel-metadata.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "active-cancel-metadata-device",
      captureDate: DateTime(2026, 6, 17, 15, 50),
      receivedDate: DateTime(2026, 6, 17, 15, 50, 1),
    );

    await SessionManager.instance.addPhoto(photo);
    final uploadFuture = uploaderService.startUploadingManually();
    await requestStarted.future.timeout(const Duration(seconds: 1));

    expect(await uploaderService.cancelCurrentUpload(), isTrue);

    final failureReason = await _readPersistedPhotoFailureReason(
      documentsDir: pathProvider.documentsDir,
      sessionGuid: "active-cancel-metadata-guid",
    );
    expect(failureReason, "Upload cancelled.");

    releaseUpload.complete();
    await requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;
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
      ..writeAsBytesSync(_validJpegBytes());
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
    expect(await uploaderService.cancelCurrentUpload(), isTrue);
    expect(client.closeCount, 1);

    await client.requestFinished.future.timeout(const Duration(seconds: 1));
    await uploadFuture;

    expect(photo.isUploaded, isFalse);
    expect(uploaderService.isUploading, isFalse);
  });

  test("cancelCurrentUpload continues draining queued media", () async {
    final releaseFirstUpload = Completer<void>();
    final firstRequestStarted = Completer<void>();
    var resumedRequestCount = 0;
    var requestCount = 0;
    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        requestCount += 1;
        if (requestCount == 1) {
          if (!firstRequestStarted.isCompleted) {
            firstRequestStarted.complete();
          }
          await releaseFirstUpload.future;
        }
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );

    SessionManager.instance.startSession(
      "cancel-drain-session-guid",
      "cancel-drain-session",
      deviceType: "Master",
    );
    final cancelledFile = File("${tempDir.path}/cancel-drain-first.jpg")
      ..writeAsBytesSync(_validJpegBytes(fill: 1));
    final queuedFile = File("${tempDir.path}/cancel-drain-second.jpg")
      ..writeAsBytesSync(_validJpegBytes(fill: 2));
    final cancelledPhoto = CapturedPhoto(
      photoPath: cancelledFile.path,
      slaveDeviceId: "cancel-drain-first",
      captureDate: DateTime(2026, 6, 18, 15, 8),
      receivedDate: DateTime(2026, 6, 18, 15, 8, 1),
    );
    final queuedPhoto = CapturedPhoto(
      photoPath: queuedFile.path,
      slaveDeviceId: "cancel-drain-second",
      captureDate: DateTime(2026, 6, 18, 15, 9),
      receivedDate: DateTime(2026, 6, 18, 15, 9, 1),
    );

    await uploaderService.addMediaToQueue(cancelledPhoto);
    await uploaderService.addMediaToQueue(queuedPhoto);
    final uploadFuture = uploaderService.startUploadingManually();
    await firstRequestStarted.future.timeout(const Duration(seconds: 1));

    expect(await uploaderService.cancelCurrentUpload(), isTrue);

    HydraCamApiService.configureHttpClient(
      MockClient.streaming((request, bodyStream) async {
        resumedRequestCount += 1;
        await bodyStream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([<int>[]]),
          200,
        );
      }),
    );
    releaseFirstUpload.complete();
    await uploadFuture;

    expect(cancelledPhoto.isUploaded, isFalse);
    expect(cancelledPhoto.uploadFailureReason, "Upload cancelled.");
    expect(queuedPhoto.isUploaded, isTrue);
    expect(queuedPhoto.uploadFailureReason, isNull);
    expect(uploaderService.queueLength, 0);
    expect(uploaderService.isUploading, isFalse);
    expect(resumedRequestCount, 1);
  });

  test("reset closes the active HTTP client", () async {
    final releaseResponse = Completer<void>();
    final client = _CloseTrackingClient(releaseResponse: releaseResponse);
    HydraCamApiService.configureHttpClient(client);

    SessionManager.instance.startSession(
      "reset-http-session-guid",
      "reset-http-session",
      deviceType: "Master",
    );
    final photoFile = File("${tempDir.path}/reset-http.jpg")
      ..writeAsBytesSync(_validJpegBytes());
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "reset-http-device",
      captureDate: DateTime(2026, 6, 17, 19, 30),
      receivedDate: DateTime(2026, 6, 17, 19, 30, 1),
    );

    await uploaderService.addMediaToQueue(photo);
    final uploadFuture = uploaderService.startUploadingManually();
    await client.requestStarted.future.timeout(const Duration(seconds: 1));

    expect(client.closeCount, 0);

    uploaderService.reset();

    expect(client.closeCount, 1);
    expect(uploaderService.isUploading, isFalse);
    expect(uploaderService.currentlyUploadingNotifier.value, isNull);

    releaseResponse.complete();
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

Future<String?> _readPersistedPhotoFailureReason({
  required Directory documentsDir,
  required String sessionGuid,
}) async {
  final metadataFile = File(
    "${documentsDir.path}/session_$sessionGuid/metadata.json",
  );
  final deadline = DateTime.now().add(const Duration(milliseconds: 500));
  String? lastFailureReason;
  while (DateTime.now().isBefore(deadline)) {
    if (metadataFile.existsSync()) {
      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      final photos = metadata["photos"] as List<dynamic>? ?? const [];
      if (photos.isNotEmpty) {
        final photo = photos.single as Map<String, dynamic>;
        lastFailureReason = photo["uploadFailureReason"]?.toString();
        if (lastFailureReason != null) {
          return lastFailureReason;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return lastFailureReason;
}

class _CloseTrackingClient extends http.BaseClient {
  _CloseTrackingClient({Completer<void>? releaseResponse})
      : _releaseResponse = releaseResponse;

  final Completer<void>? _releaseResponse;
  final Completer<void> requestStarted = Completer<void>();
  final Completer<void> requestFinished = Completer<void>();
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requestStarted.isCompleted) {
      requestStarted.complete();
    }
    await request.finalize().drain<void>();
    await _releaseResponse?.future;
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
