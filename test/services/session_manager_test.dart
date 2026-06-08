import "dart:io";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/session_manager.dart";
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
    late Directory tempMediaDir;

    setUp(() async {
      sessionManager = SessionManager.instance;
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

      test("endSession clears session state", () async {
        sessionManager.startSession("test-guid", "test-id",
            deviceType: "Master");
        await sessionManager.endSession();

        expect(sessionManager.isSessionActive, false);
        expect(sessionManager.sessionGuid, null);
      });
    });

    group("Media management", () {
      setUp(() {
        sessionManager.startSession("test-guid", "test-id",
            deviceType: "Master");
      });

      test("addPhoto adds photo to current session", () {
        final photoPath = createTempMediaFile("test_photo.jpg");
        final photo = CapturedPhoto(
          photoPath: photoPath,
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );

        sessionManager.addPhoto(photo);

        expect(sessionManager.currentSession?.capturedPhotos.length, 1);
        expect(sessionManager.currentSession?.capturedPhotos.first, photo);
      });

      test("addVideo adds video to current session", () {
        final videoPath = createTempMediaFile("test_video.mp4");
        final video = CapturedVideo(
          videoPath: videoPath,
          videoData: null,
          slaveDeviceId: "device-1",
          startRecordingDate: DateTime.now(),
          endRecordingDate: DateTime.now(),
          receivedDate: DateTime.now(),
        );

        sessionManager.addVideo(video);

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

        sessionManager.addVideo(video);
        await sessionManager.updateMetadata();

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

      test("multiple media can be added to session", () {
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

        sessionManager.addPhoto(photo1);
        sessionManager.addPhoto(photo2);

        expect(sessionManager.currentSession?.capturedPhotos.length, 2);
      });
    });
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("session_manager_docs");
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
