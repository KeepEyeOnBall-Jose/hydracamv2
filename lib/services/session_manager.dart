import 'package:flutter/foundation.dart';
import 'package:sport_cam_sync/services/settings_service.dart';
import 'package:sport_cam_sync/services/uploader_service.dart';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'log_service.dart';
import 'dart:io';

/// A global manager to handle session-related information across Master and Slave.
/// Provides a centralized place to access the current session and its GUID.
class SessionManager extends ChangeNotifier {
  /// Singleton instance
  static final SessionManager _instance = SessionManager._internal();

  /// Private constructor for singleton
  SessionManager._internal();

  /// Accessor for singleton instance
  static SessionManager get instance => _instance;

  /// The unique identifier for the current session (GUID).
  String? _sessionGuid;

  /// The `CaptureSession` object for tracking media in the current session.
  CaptureSession? _currentSession;

  /// The type of device (Master or Slave) for this instance.
  String _deviceType = "Unknown";

  /// Getters for session data
  String? get sessionGuid => _sessionGuid;
  CaptureSession? get currentSession => _currentSession;
  String get deviceType => _deviceType;
  bool get isSessionActive => _currentSession != null;

  /// Set the session GUID and initialize a new `CaptureSession`.
  void startSession(String sessionGuid, {required String deviceType}) {
    _sessionGuid = sessionGuid;
    _deviceType = deviceType;
    _currentSession = CaptureSession(
      sessionId: sessionGuid,
      startTime: DateTime.now(),
    );
    LogService.instance.registerLog("Session started with GUID: $_sessionGuid on device type: $_deviceType");
    notifyListeners();
  }

  /// Ends the current session, clearing data.
  void endSession() {
    _currentSession?.endSession();
    _currentSession = null;
    _sessionGuid = null;
    notifyListeners();
  }

  /// Add a captured photo to the current session.
  void addPhoto(CapturedPhoto photo) {

    // Add photo to session and notify listeners
    _currentSession?.addPhoto(photo);
    notifyListeners();

    LogService.instance.registerLog("Adding photo to upload queue: ${photo.photoPath}");

    // Add photo to uploader queue
    UploaderService().addMediaToQueue(photo);

  }

  /// Add a captured video to the current session.
  void addVideo(CapturedVideo video) {

    // Add video to session and notify listeners
    _currentSession?.addVideo(video);
    notifyListeners();

    LogService.instance.registerLog("Adding video to upload queue: ${video.videoPath}");

    // Add video to uploader queue
    UploaderService().addMediaToQueue(video);

  }

  /// Deletes a file if the setting to delete local files is enabled.
  Future<void> deleteFileIfAllowed(String filePath) async {
    final shouldDelete = await SettingsService.getDeleteLocalAfterUpload();
    if (shouldDelete) {
      final file = File(filePath);
      if (await file.exists()) {
        try {
          await file.delete();
          LogService.instance.registerLog("Deleted local file: $filePath");
        } catch (e) {
          LogService.instance.registerLog("Failed to delete file: $filePath, error: $e");
        }
      } else {
        LogService.instance.registerLog("File not found for deletion: $filePath");
      }
    }
  }
}
