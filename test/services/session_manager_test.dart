import "dart:io";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/session_manager.dart";
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

    String _createTempMediaFile(String name) {
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
        final photoPath = _createTempMediaFile("test_photo.jpg");
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
        final videoPath = _createTempMediaFile("test_video.mp4");
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

      test("multiple media can be added to session", () {
        final photoPath1 = _createTempMediaFile("test_photo_1.jpg");
        final photoPath2 = _createTempMediaFile("test_photo_2.jpg");
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

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("session_manager_docs");
    return _documentsDir!.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
