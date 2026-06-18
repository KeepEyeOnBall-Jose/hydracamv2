import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Unit tests for SessionManager
///
/// These tests verify session lifecycle and media management.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _TestPathProviderPlatform testPathProvider =
      _TestPathProviderPlatform();

  setUpAll(() async {
    PathProviderPlatform.instance = testPathProvider;
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
  });

  tearDownAll(() {
    testPathProvider.dispose();
  });

  group("SessionManager", () {
    late SessionManager sessionManager;
    late UploaderService uploaderService;
    late Directory tempMediaDir;

    setUp(() async {
      sessionManager = SessionManager.instance;
      uploaderService = UploaderService();
      uploaderService.reset();
      tempMediaDir =
          Directory.systemTemp.createTempSync("session_manager_test_media");
      // Reset state before each test
      if (sessionManager.isSessionActive) {
        await sessionManager.endSession();
      }
    });

    tearDown(() async {
      if (sessionManager.isSessionActive) {
        await sessionManager.endSession();
      }

      if (tempMediaDir.existsSync()) {
        tempMediaDir.deleteSync(recursive: true);
      }
    });

    String createTempMediaFile(String name) {
      final file = File("${tempMediaDir.path}/$name");
      file.createSync(recursive: true);
      file.writeAsBytesSync(List<int>.filled(5, 42));
      return file.path;
    }

    group("Session lifecycle", () {
      test("starts with no active session", () {
        expect(sessionManager.isSessionActive, false);
        expect(sessionManager.sessionGuid, null);
      });

      test("startSession creates new session", () {
        sessionManager.startSession("test-guid", "test-id",
            deviceType: "Master");

        expect(sessionManager.isSessionActive, true);
        expect(sessionManager.sessionGuid, "test-guid");
      });

      test("startCreatedSession starts a service-created session", () {
        sessionManager.startCreatedSession(
          const HydraCamBackendSession(
            guid: "backend-guid",
            sessionId: "backend-session",
          ),
          deviceType: "Master",
        );

        expect(sessionManager.isSessionActive, true);
        expect(sessionManager.sessionGuid, "backend-guid");
        expect(sessionManager.canUploadCurrentSession, isTrue);
      });

      test("startCreatedSession rejects non-service GUIDs", () {
        expect(
          () => sessionManager.startCreatedSession(
            const HydraCamBackendSession(
              guid: "local-backend-guid",
              sessionId: "debug-request",
            ),
            deviceType: "Master",
          ),
          throwsArgumentError,
        );
      });

      test("joinSession rejects non-service GUIDs", () {
        expect(
          () => sessionManager.joinSession(
            "local-slave-guid",
            "slave-session",
            deviceType: "Slave",
          ),
          throwsArgumentError,
        );
      });

      test("canUploadCurrentSession requires an active service GUID", () {
        sessionManager.startSession(
          "service-session-guid",
          "session-id",
          deviceType: "Master",
        );

        expect(sessionManager.canUploadCurrentSession, isTrue);
      });

      test("endSession clears session state", () async {
        sessionManager.startSession("test-guid", "test-id",
            deviceType: "Master");
        await sessionManager.endSession();

        expect(sessionManager.isSessionActive, false);
        expect(sessionManager.sessionGuid, null);
      });

      test("scanAndReconstructSessions preserves active session identity",
          () async {
        sessionManager.startSession("active-guid", "active-id",
            deviceType: "Slave");

        final oldSessionDir = Directory(
            "${testPathProvider.documentsDir.path}/session_scan-preserve-old");
        if (oldSessionDir.existsSync()) {
          oldSessionDir.deleteSync(recursive: true);
        }
        oldSessionDir.createSync(recursive: true);
        File("${oldSessionDir.path}/old-video.mp4")
            .writeAsBytesSync([1, 2, 3, 4]);
        final nonSessionDir =
            Directory("${testPathProvider.documentsDir.path}/camera_roll");
        if (nonSessionDir.existsSync()) {
          nonSessionDir.deleteSync(recursive: true);
        }
        nonSessionDir.createSync(recursive: true);
        File("${nonSessionDir.path}/stray-video.mp4")
            .writeAsBytesSync([4, 3, 2, 1]);

        final reconstructed = await sessionManager.scanAndReconstructSessions();

        expect(reconstructed, contains("scan-preserve-old"));
        expect(reconstructed, isNot(contains("camera_roll")));
        expect(sessionManager.sessionGuid, "active-guid");
        expect(sessionManager.deviceType, "Slave");
        expect(sessionManager.currentSession?.sessionGuid, "active-guid");
      });

      test("scanAndReconstructSessions preserves full directory session id",
          () async {
        const sessionIdentifier = "scan_preserve_full_guid";
        final sessionDir = Directory(
          "${testPathProvider.documentsDir.path}/session_$sessionIdentifier",
        );
        if (sessionDir.existsSync()) {
          sessionDir.deleteSync(recursive: true);
        }
        sessionDir.createSync(recursive: true);
        File("${sessionDir.path}/underscore-video.mp4")
            .writeAsBytesSync([1, 2, 3, 4]);

        final reconstructed = await sessionManager.scanAndReconstructSessions();

        expect(reconstructed, contains(sessionIdentifier));
        expect(reconstructed, isNot(contains("guid")));

        final metadataFile = File("${sessionDir.path}/metadata.json");
        expect(metadataFile.existsSync(), isTrue);
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        expect(metadata["sessionId"], sessionIdentifier);
        expect(metadata["sessionGuid"], sessionIdentifier);
      });

      test("scanAndReconstructSessions repairs blank stored session guid",
          () async {
        const sessionIdentifier = "scan-repair-blank-guid";
        final sessionDir = Directory(
          "${testPathProvider.documentsDir.path}/session_$sessionIdentifier",
        );
        if (sessionDir.existsSync()) {
          sessionDir.deleteSync(recursive: true);
        }
        sessionDir.createSync(recursive: true);
        final metadataFile = File("${sessionDir.path}/metadata.json");
        await metadataFile.writeAsString(
          jsonEncode({
            "sessionId": "legacy-scan-id",
            "sessionGuid": "  ",
            "startTime": DateTime.utc(2026, 6, 18, 16, 10).toIso8601String(),
            "endTime": null,
            "deviceType": "Master",
            "photos": [],
            "videos": [],
          }),
        );

        final reconstructed = await sessionManager.scanAndReconstructSessions();

        expect(reconstructed, contains(sessionIdentifier));
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        expect(metadata["sessionId"], "legacy-scan-id");
        expect(metadata["sessionGuid"], sessionIdentifier);
      });

      test("loadSessionMetadataSnapshot preserves active session identity",
          () async {
        sessionManager.startSession("active-guid", "active-id",
            deviceType: "Slave");

        final oldSessionDir =
            Directory("${testPathProvider.documentsDir.path}/session_old-guid");
        oldSessionDir.createSync(recursive: true);
        await File("${oldSessionDir.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "old-id",
            "sessionGuid": "old-guid",
            "startTime": DateTime.utc(2026, 6, 8, 9).toIso8601String(),
            "endTime": DateTime.utc(2026, 6, 8, 9, 30).toIso8601String(),
            "deviceType": "Master",
            "photos": [],
            "videos": [],
          }),
        );

        final snapshot =
            await sessionManager.loadSessionMetadataSnapshot("old-guid");

        expect(snapshot?.sessionId, "old-id");
        expect(snapshot?.sessionGuid, "old-guid");
        expect(sessionManager.sessionGuid, "active-guid");
        expect(sessionManager.deviceType, "Slave");
        expect(sessionManager.currentSession?.sessionGuid, "active-guid");
      });

      test("loadSessionMetadata previews without replacing active session",
          () async {
        sessionManager.startSession("active-preview-guid", "active-preview-id",
            deviceType: "Master");

        final oldSessionDir = Directory(
            "${testPathProvider.documentsDir.path}/session_previous-preview-guid");
        oldSessionDir.createSync(recursive: true);
        await File("${oldSessionDir.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "previous-preview-id",
            "sessionGuid": "previous-preview-guid",
            "startTime": DateTime.utc(2026, 6, 17, 10).toIso8601String(),
            "endTime": DateTime.utc(2026, 6, 17, 10, 30).toIso8601String(),
            "deviceType": "Slave",
            "photos": [],
            "videos": [],
          }),
        );

        final preview =
            await sessionManager.loadSessionMetadata("previous-preview-guid");

        expect(preview?.sessionId, "previous-preview-id");
        expect(preview?.sessionGuid, "previous-preview-guid");
        expect(sessionManager.sessionGuid, "active-preview-guid");
        expect(
          sessionManager.currentSession?.sessionGuid,
          "active-preview-guid",
        );
        expect(sessionManager.deviceType, "Master");
      });

      test("loadSessionMetadataSnapshot tolerates cleaned-up media files",
          () async {
        final cleanedSessionDir = Directory(
            "${testPathProvider.documentsDir.path}/session_cleaned-media-guid");
        cleanedSessionDir.createSync(recursive: true);
        final missingPhotoPath = "${cleanedSessionDir.path}/deleted-photo.jpg";
        final missingVideoPath = "${cleanedSessionDir.path}/deleted-video.mp4";
        await File("${cleanedSessionDir.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "cleaned-media-id",
            "sessionGuid": "cleaned-media-guid",
            "startTime": DateTime.utc(2026, 6, 17, 16).toIso8601String(),
            "endTime": DateTime.utc(2026, 6, 17, 16, 30).toIso8601String(),
            "deviceType": "Master",
            "photos": [
              {
                "photoPath": missingPhotoPath,
                "slaveDeviceId": "photo-device",
                "captureDate":
                    DateTime.utc(2026, 6, 17, 16, 1).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 17, 16, 2).toIso8601String(),
                "isUploaded": true,
                "fileSizeInBytes": 1234,
              },
            ],
            "videos": [
              {
                "videoPath": missingVideoPath,
                "slaveDeviceId": "video-device",
                "startRecordingDate":
                    DateTime.utc(2026, 6, 17, 16, 3).toIso8601String(),
                "endRecordingDate":
                    DateTime.utc(2026, 6, 17, 16, 4).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 17, 16, 5).toIso8601String(),
                "isUploaded": true,
                "fileSizeInBytes": 5678,
              },
            ],
          }),
        );

        final snapshot = await sessionManager.loadSessionMetadataSnapshot(
          "cleaned-media-guid",
        );

        expect(snapshot?.capturedPhotos.single.photoPath, missingPhotoPath);
        expect(snapshot?.capturedPhotos.single.fileSizeInBytes, 1234);
        expect(snapshot?.capturedVideos.single.videoPath, missingVideoPath);
        expect(snapshot?.capturedVideos.single.fileSizeInBytes, 5678);
      });

      test("loadSessionMetadataSnapshot skips malformed media rows", () async {
        LogService.instance.clearLogs();
        sessionManager.startSession("active-metadata-guid", "active-id",
            deviceType: "Master");

        final mixedSessionDir = Directory(
            "${testPathProvider.documentsDir.path}/session_mixed-media-guid");
        mixedSessionDir.createSync(recursive: true);
        final validPhotoPath = createTempMediaFile("valid_history_photo.jpg");
        final validVideoPath = createTempMediaFile("valid_history_video.mp4");
        await File("${mixedSessionDir.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "mixed-media-id",
            "sessionGuid": "mixed-media-guid",
            "startTime": DateTime.utc(2026, 6, 18, 12).toIso8601String(),
            "endTime": DateTime.utc(2026, 6, 18, 12, 30).toIso8601String(),
            "deviceType": "Master",
            "photos": [
              {
                "photoPath": validPhotoPath,
                "slaveDeviceId": "valid-photo-device",
                "captureDate":
                    DateTime.utc(2026, 6, 18, 12, 1).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 18, 12, 2).toIso8601String(),
                "isUploaded": true,
              },
              {
                "photoPath": "bad-photo.jpg",
                "slaveDeviceId": "bad-photo-device",
                "captureDate": "not-a-date",
                "receivedDate":
                    DateTime.utc(2026, 6, 18, 12, 3).toIso8601String(),
              },
            ],
            "videos": [
              {
                "videoPath": "bad-video.mp4",
                "slaveDeviceId": "bad-video-device",
                "startRecordingDate":
                    DateTime.utc(2026, 6, 18, 12, 4).toIso8601String(),
                "endRecordingDate": "not-a-date",
                "receivedDate":
                    DateTime.utc(2026, 6, 18, 12, 5).toIso8601String(),
              },
              {
                "videoPath": validVideoPath,
                "slaveDeviceId": "valid-video-device",
                "startRecordingDate":
                    DateTime.utc(2026, 6, 18, 12, 6).toIso8601String(),
                "endRecordingDate":
                    DateTime.utc(2026, 6, 18, 12, 7).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 18, 12, 8).toIso8601String(),
                "isUploaded": true,
              },
            ],
          }),
        );

        final snapshot = await sessionManager.loadSessionMetadataSnapshot(
          "mixed-media-guid",
        );

        expect(snapshot?.capturedPhotos, hasLength(1));
        expect(snapshot?.capturedPhotos.single.photoPath, validPhotoPath);
        expect(snapshot?.capturedVideos, hasLength(1));
        expect(snapshot?.capturedVideos.single.videoPath, validVideoPath);
        expect(sessionManager.sessionGuid, "active-metadata-guid");
        expect(
          LogService.instance.logs.map((entry) => entry["message"]),
          contains(
            predicate<Object?>(
              (message) =>
                  message is String &&
                  message.startsWith(
                    "Skipped invalid stored photo metadata for session "
                    "mixed-media-guid at index 1:",
                  ),
            ),
          ),
        );
        expect(
          LogService.instance.logs.map((entry) => entry["message"]),
          contains(
            predicate<Object?>(
              (message) =>
                  message is String &&
                  message.startsWith(
                    "Skipped invalid stored video metadata for session "
                    "mixed-media-guid at index 0:",
                  ),
            ),
          ),
        );
      });

      test("rejoining same active session preserves media and upload queue",
          () async {
        sessionManager.startSession("same-guid", "same-id",
            deviceType: "Master");
        final photoPath = createTempMediaFile("same_session_photo.jpg");
        final photo = CapturedPhoto(
          photoPath: photoPath,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );
        await sessionManager.addPhoto(photo);

        expect(sessionManager.currentSession?.capturedPhotos, [photo]);
        expect(uploaderService.queueLength, 1);

        sessionManager.startSession("same-guid", "same-id",
            deviceType: "Slave");

        expect(sessionManager.sessionGuid, "same-guid");
        expect(sessionManager.deviceType, "Slave");
        expect(sessionManager.currentSession?.capturedPhotos, [photo]);
        expect(uploaderService.queueLength, 1);
      });

      test("joining a different session starts with clean media state",
          () async {
        sessionManager.startSession("old-guid", "old-id", deviceType: "Master");
        final photoPath = createTempMediaFile("old_session_photo.jpg");
        final photo = CapturedPhoto(
          photoPath: photoPath,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );
        await sessionManager.addPhoto(photo);

        expect(sessionManager.currentSession?.capturedPhotos, [photo]);
        expect(uploaderService.queueLength, 1);

        sessionManager.startSession("new-guid", "new-id", deviceType: "Master");

        expect(sessionManager.sessionGuid, "new-guid");
        expect(sessionManager.currentSession?.capturedPhotos, isEmpty);
        expect(uploaderService.queueLength, 0);
      });

      test("addPhoto can be awaited through metadata and enqueue", () async {
        const sessionGuid = "await-photo-guid";
        sessionManager.startSession(sessionGuid, "await-photo-id",
            deviceType: "Master");
        final photoPath = createTempMediaFile("await_photo.jpg");
        final photo = CapturedPhoto(
          photoPath: photoPath,
          photoData: null,
          captureDate: DateTime.utc(2026, 6, 9, 2, 28),
          receivedDate: DateTime.utc(2026, 6, 9, 2, 28, 1),
          slaveDeviceId: "await-photo-device",
        );

        await sessionManager.addPhoto(photo);

        final metadataFile = File(
            "${testPathProvider.documentsDir.path}/session_$sessionGuid/metadata.json");
        expect(metadataFile.existsSync(), isTrue);
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        expect(metadata["photos"], hasLength(1));
        expect(metadata["photos"].single["photoPath"], photoPath);
        expect(metadata["photos"].single["fileSizeInBytes"], 5);
        expect(uploaderService.queueLength, 1);
      });

      test("addVideo can be awaited through metadata and enqueue", () async {
        const sessionGuid = "await-video-guid";
        sessionManager.startSession(sessionGuid, "await-video-id",
            deviceType: "Slave");
        final videoPath = createTempMediaFile("await_video.mp4");
        final video = CapturedVideo(
          videoPath: videoPath,
          videoData: null,
          startRecordingDate: DateTime.utc(2026, 6, 9, 2, 29),
          endRecordingDate: DateTime.utc(2026, 6, 9, 2, 29, 5),
          receivedDate: DateTime.utc(2026, 6, 9, 2, 29, 6),
          slaveDeviceId: "await-video-device",
        );

        await sessionManager.addVideo(video);

        final metadataFile = File(
            "${testPathProvider.documentsDir.path}/session_$sessionGuid/metadata.json");
        expect(metadataFile.existsSync(), isTrue);
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        expect(metadata["videos"], hasLength(1));
        expect(metadata["videos"].single["videoPath"], videoPath);
        expect(metadata["videos"].single["fileSizeInBytes"], 5);
        expect(uploaderService.queueLength, 1);
      });

      test("restoreSessionFromMetadata restores media and caller role",
          () async {
        final restoredPhotoPath = createTempMediaFile("restored_photo.jpg");
        final restoredVideoPath = createTempMediaFile("restored_video.mp4");
        final sessionDirectory = Directory(
            "${testPathProvider.documentsDir.path}/session_restore-guid");
        sessionDirectory.createSync(recursive: true);
        await File("${sessionDirectory.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "restore-id",
            "sessionGuid": "restore-guid",
            "startTime": DateTime.utc(2026, 6, 9, 1).toIso8601String(),
            "endTime": null,
            "deviceType": "Slave",
            "photos": [
              {
                "photoPath": restoredPhotoPath,
                "slaveDeviceId": "photo-device",
                "captureDate": DateTime.utc(2026, 6, 9, 1, 1).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 9, 1, 2).toIso8601String(),
                "isUploaded": false,
              },
            ],
            "videos": [
              {
                "videoPath": restoredVideoPath,
                "slaveDeviceId": "video-device",
                "startRecordingDate":
                    DateTime.utc(2026, 6, 9, 1, 3).toIso8601String(),
                "endRecordingDate":
                    DateTime.utc(2026, 6, 9, 1, 4).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 9, 1, 5).toIso8601String(),
                "isUploaded": false,
              },
            ],
          }),
        );

        final restored = await sessionManager.restoreSessionFromMetadata(
          "restore-guid",
          deviceType: "Master",
        );

        expect(restored.sessionId, "restore-id");
        expect(restored.sessionGuid, "restore-guid");
        expect(sessionManager.sessionGuid, "restore-guid");
        expect(sessionManager.deviceType, "Master");
        expect(sessionManager.currentSession?.sessionId, "restore-id");
        expect(sessionManager.currentSession?.capturedPhotos.single.photoPath,
            restoredPhotoPath);
        expect(sessionManager.currentSession?.capturedVideos.single.videoPath,
            restoredVideoPath);
        expect(uploaderService.queueLength, 2);
      });

      test("restoreSessionFromMetadata does not requeue uploaded media",
          () async {
        final restoredPhotoPath = createTempMediaFile("uploaded_photo.jpg");
        final restoredVideoPath = createTempMediaFile("uploaded_video.mp4");
        final sessionDirectory = Directory(
            "${testPathProvider.documentsDir.path}/session_uploaded-restore-guid");
        sessionDirectory.createSync(recursive: true);
        await File("${sessionDirectory.path}/metadata.json").writeAsString(
          jsonEncode({
            "sessionId": "uploaded-restore-id",
            "sessionGuid": "uploaded-restore-guid",
            "startTime": DateTime.utc(2026, 6, 17, 17).toIso8601String(),
            "endTime": null,
            "deviceType": "Master",
            "photos": [
              {
                "photoPath": restoredPhotoPath,
                "slaveDeviceId": "uploaded-photo-device",
                "captureDate":
                    DateTime.utc(2026, 6, 17, 17, 1).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 17, 17, 2).toIso8601String(),
                "isUploaded": true,
                "fileSizeInBytes": 5,
              },
            ],
            "videos": [
              {
                "videoPath": restoredVideoPath,
                "slaveDeviceId": "uploaded-video-device",
                "startRecordingDate":
                    DateTime.utc(2026, 6, 17, 17, 3).toIso8601String(),
                "endRecordingDate":
                    DateTime.utc(2026, 6, 17, 17, 4).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 17, 17, 5).toIso8601String(),
                "isUploaded": true,
                "fileSizeInBytes": 5,
              },
            ],
          }),
        );

        await sessionManager.restoreSessionFromMetadata(
          "uploaded-restore-guid",
          deviceType: "Master",
        );

        expect(sessionManager.currentSession?.capturedPhotos.single.isUploaded,
            isTrue);
        expect(sessionManager.currentSession?.capturedVideos.single.isUploaded,
            isTrue);
        expect(uploaderService.queueLength, 0);
      });

      test("restoreSessionFromMetadata repairs blank stored session guid",
          () async {
        final restoredPhotoPath = createTempMediaFile("blank_guid_photo.jpg");
        final sessionDirectory = Directory(
            "${testPathProvider.documentsDir.path}/session_backend-restore-guid");
        sessionDirectory.createSync(recursive: true);
        final metadataFile = File("${sessionDirectory.path}/metadata.json");
        await metadataFile.writeAsString(
          jsonEncode({
            "sessionId": "legacy-blank-guid-id",
            "sessionGuid": "  ",
            "startTime": DateTime.utc(2026, 6, 18, 15).toIso8601String(),
            "endTime": null,
            "deviceType": "Slave",
            "photos": [
              {
                "photoPath": restoredPhotoPath,
                "slaveDeviceId": "blank-guid-photo-device",
                "captureDate":
                    DateTime.utc(2026, 6, 18, 15, 1).toIso8601String(),
                "receivedDate":
                    DateTime.utc(2026, 6, 18, 15, 2).toIso8601String(),
                "isUploaded": false,
                "fileSizeInBytes": 5,
              },
            ],
            "videos": [],
          }),
        );

        final restored = await sessionManager.restoreSessionFromMetadata(
          "backend-restore-guid",
          deviceType: "Master",
        );

        expect(restored.sessionGuid, "backend-restore-guid");
        expect(restored.preferredIdentifier, "backend-restore-guid");
        expect(sessionManager.sessionGuid, "backend-restore-guid");
        expect(
            sessionManager.currentSession?.sessionId, "legacy-blank-guid-id");
        expect(uploaderService.queueLength, 1);

        final repairedMetadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        expect(repairedMetadata["sessionGuid"], "backend-restore-guid");
      });
    });

    group("Media management", () {
      setUp(() {
        sessionManager.startSession("test-guid", "test-id",
            deviceType: "Master");
      });

      test("addPhoto adds photo to current session", () async {
        final photoPath = createTempMediaFile("test_photo.jpg");
        final photo = CapturedPhoto(
          photoPath: photoPath,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );

        await sessionManager.addPhoto(photo);

        expect(sessionManager.currentSession?.capturedPhotos.length, 1);
        expect(sessionManager.currentSession?.capturedPhotos.first, photo);
      });

      test("addVideo adds video to current session", () async {
        final videoPath = createTempMediaFile("test_video.mp4");
        final video = CapturedVideo(
          videoPath: videoPath,
          videoData: null,
          slaveDeviceId: "device-1",
          startRecordingDate: DateTime.now(),
          endRecordingDate: DateTime.now(),
          receivedDate: DateTime.now(),
        );

        await sessionManager.addVideo(video);

        expect(sessionManager.currentSession?.capturedVideos.length, 1);
        expect(sessionManager.currentSession?.capturedVideos.first, video);
      });

      test("video capture context persists and reloads from metadata",
          () async {
        final videoPath = createTempMediaFile("context_video.mp4");
        final capturedAt = DateTime.utc(2026, 6, 8, 12);
        final video = CapturedVideo(
          videoPath: videoPath,
          videoData: null,
          slaveDeviceId: "device-1",
          startRecordingDate: capturedAt,
          endRecordingDate: capturedAt.add(const Duration(seconds: 3)),
          receivedDate: capturedAt.add(const Duration(seconds: 4)),
          captureContext: MediaCaptureContext(
            perspective: CameraPerspectiveMetadata.fromId(
              "center_backglass_parallel",
            ),
            level: DeviceLevelMetadata(
              rollDegrees: 1.5,
              pitchDegrees: -2.5,
              toleranceDegrees: 5,
              isLevel: true,
              sensorAvailable: true,
              capturedAt: capturedAt,
            ),
            cameraName: "0",
            cameraLensDirection: "back",
            cameraSensorOrientation: 90,
            videoCaptureProfile: "sport1080p60",
            deviceId: "device-1",
          ),
        );

        await sessionManager.addVideo(video);

        final metadataFile = File(
          "${testPathProvider.documentsDir.path}/session_test-guid/metadata.json",
        );
        final metadata = await metadataFile.readAsString();
        expect(metadata, contains("center_backglass_parallel"));
        expect(metadata, contains("deviceLevel"));

        final loaded = await sessionManager.loadSessionMetadata("test-guid");
        final loadedContext = loaded?.capturedVideos.single.captureContext;

        expect(
          loadedContext?.perspective.cameraPerspectiveId,
          "center_backglass_parallel",
        );
        expect(loadedContext?.level.rollDegrees, 1.5);
        expect(loadedContext?.videoCaptureProfile, "sport1080p60");
      });

      test("metadata write preserves session captured before async path lookup",
          () async {
        const oldGuid = "metadata-old-guid";
        const newGuid = "metadata-new-guid";
        final oldSessionDir =
            Directory("${testPathProvider.documentsDir.path}/session_$oldGuid");
        final newSessionDir =
            Directory("${testPathProvider.documentsDir.path}/session_$newGuid");
        if (oldSessionDir.existsSync()) {
          oldSessionDir.deleteSync(recursive: true);
        }
        if (newSessionDir.existsSync()) {
          newSessionDir.deleteSync(recursive: true);
        }

        sessionManager.startSession(oldGuid, "metadata-old-id",
            deviceType: "Master");

        final releaseFirstPathLookup = Completer<void>();
        testPathProvider.blockNextPathLookupUntil(
          releaseFirstPathLookup.future,
        );

        final pendingOldSessionSave = sessionManager.updateMetadata();
        await Future<void>.delayed(Duration.zero);

        sessionManager.startSession(newGuid, "metadata-new-id",
            deviceType: "Slave");
        releaseFirstPathLookup.complete();
        await pendingOldSessionSave;

        final oldMetadataFile = File("${oldSessionDir.path}/metadata.json");
        final newMetadataFile = File("${newSessionDir.path}/metadata.json");

        expect(oldMetadataFile.existsSync(), isTrue);
        expect(newMetadataFile.existsSync(), isFalse);

        final metadata = jsonDecode(await oldMetadataFile.readAsString());
        expect(metadata["sessionId"], "metadata-old-id");
        expect(metadata["sessionGuid"], oldGuid);
        expect(metadata["deviceType"], "Master");
      });

      test("multiple media can be added to session", () async {
        final photoPath1 = createTempMediaFile("test_photo_1.jpg");
        final photoPath2 = createTempMediaFile("test_photo_2.jpg");
        final photo1 = CapturedPhoto(
          photoPath: photoPath1,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );
        final photo2 = CapturedPhoto(
          photoPath: photoPath2,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-2",
        );

        await sessionManager.addPhoto(photo1);
        await sessionManager.addPhoto(photo2);

        expect(sessionManager.currentSession?.capturedPhotos.length, 2);
      });
    });
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;
  Future<void>? _nextPathLookupBlocker;

  Directory get documentsDir {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("session_manager_docs");
    return _documentsDir!;
  }

  void blockNextPathLookupUntil(Future<void> blocker) {
    _nextPathLookupBlocker = blocker;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final blocker = _nextPathLookupBlocker;
    if (blocker != null) {
      _nextPathLookupBlocker = null;
      await blocker;
    }
    return documentsDir.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
