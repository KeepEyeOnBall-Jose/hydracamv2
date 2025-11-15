import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";

/// Unit tests for SessionManager
///
/// These tests verify session lifecycle and media management.

void main() {
  group("SessionManager", () {
    late SessionManager sessionManager;

    setUp(() {
      sessionManager = SessionManager.instance;
      // Reset state before each test
      if (sessionManager.isSessionActive) {
        sessionManager.endSession();
      }
    });

    group("Session lifecycle", () {
      test("starts with no active session", () {
        expect(sessionManager.isSessionActive, false);
        expect(sessionManager.sessionGuid, null);
      });

      test("startSession creates new session", () {
        sessionManager.startSession("test-guid", "test-id", deviceType: "Master");

        expect(sessionManager.isSessionActive, true);
        expect(sessionManager.sessionGuid, "test-guid");
      });

      test("endSession clears session state", () {
        sessionManager.startSession("test-guid", "test-id", deviceType: "Master");
        sessionManager.endSession();

        expect(sessionManager.isSessionActive, false);
        expect(sessionManager.sessionGuid, null);
      });
    });

    group("Media management", () {
      setUp(() {
        sessionManager.startSession("test-guid", "test-id", deviceType: "Master");
      });

      test("addPhoto adds photo to current session", () {
        final photo = CapturedPhoto(
          photoPath: "/test/path.jpg",
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
        final video = CapturedVideo(
          videoPath: "/test/video.mp4",
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
        final photo1 = CapturedPhoto(
          photoPath: "/test/1.jpg",
          photoData: null,
          captureDate: DateTime.now(),
          receivedDate: DateTime.now(),
          slaveDeviceId: "device-1",
        );
        final photo2 = CapturedPhoto(
          photoPath: "/test/2.jpg",
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

