import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "settings_service.dart";
import "uploader_service.dart";
import "package:path_provider/path_provider.dart";
import "../models/capture_session.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "device_service.dart";
import "log_service.dart";
import "dart:io";

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
  void startSession(String sessionGuid, String? sessionId,
      {required String deviceType}) {
    // Reset UploaderService to ensure a clean state for the new session
    UploaderService().reset();

    // Set the session GUID and initialize a new session object
    _sessionGuid = sessionGuid;
    _deviceType = deviceType;
    _currentSession = CaptureSession(
      sessionId: sessionId ?? sessionGuid,
      sessionGuid: sessionGuid,
      startTime: DateTime.now(),
    );

    // Log session start and notify listeners
    LogService.instance.registerLog(
        "Session started with GUID: $_sessionGuid on device type: $_deviceType");
    notifyListeners();
  }

  /// Ends the current session, clearing data.
  Future<void> endSession() async {
    if (_currentSession == null) {
      LogService.instance.registerLog("No active session to end.");
      return;
    }

    // End current session
    _currentSession?.endSession();
    // Update metadata.json file
    await updateMetadata();

    // Clean variables
    _currentSession = null;
    _sessionGuid = null;

    // Reset the uploader to clear any pending operations
    UploaderService().reset();

    // Log operation and notify UI
    LogService.instance.registerLog("Session ended and uploader reset.");
    notifyListeners();
  }

  /// Add a captured photo to the current session.
  void addPhoto(CapturedPhoto photo) {
    // Add photo to session and notify listeners
    _currentSession?.addPhoto(photo);
    notifyListeners();

    LogService.instance
        .registerLog("Adding photo to upload queue: ${photo.photoPath}");

    // Update metadata
    updateMetadata();

    // Add photo to uploader queue
    UploaderService().addMediaToQueue(photo);
  }

  /// Add a captured video to the current session.
  void addVideo(CapturedVideo video) {
    // Add video to session and notify listeners
    _currentSession?.addVideo(video);
    notifyListeners();

    LogService.instance
        .registerLog("Adding video to upload queue: ${video.videoPath}");

    // Update metadata
    updateMetadata();

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
          LogService.instance
              .registerLog("Failed to delete file: $filePath, error: $e");
        }
      } else {
        LogService.instance
            .registerLog("File not found for deletion: $filePath");
      }
    }
  }

  /// --------------------------------
  /// METHODS FOR PERSISTENT SESSIONS
  /// --------------------------------

  // For writing session metadata
  Future<void> saveSessionMetadata() async {
    if (_currentSession == null || _sessionGuid == null) {
      LogService.instance.registerLog(
          "No active session or session GUID is null. Skipping metadata save.");
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory(
          "${directory.path}/session_${_currentSession!.sessionGuid}");
      if (!sessionDirectory.existsSync()) {
        sessionDirectory.createSync(recursive: true);
      }

      final metadataFile = File("${sessionDirectory.path}/metadata.json");
      final metadata = {
        "sessionId": _currentSession!.sessionId,
        "sessionGuid": _sessionGuid,
        "startTime": _currentSession!.startTime.toIso8601String(),
        "endTime": _currentSession!.endTime?.toIso8601String(),
        "deviceType": _deviceType,
        "photos": _currentSession!.capturedPhotos
            .map((photo) => {
                  "photoPath": photo.photoPath,
                  "slaveDeviceId": photo.slaveDeviceId,
                  "captureDate": photo.captureDate.toIso8601String(),
                  "receivedDate": photo.receivedDate.toIso8601String(),
                  "isUploaded": photo.isUploaded,
                })
            .toList(),
        "videos": _currentSession!.capturedVideos
            .map((video) => {
                  "videoPath": video.videoPath,
                  "slaveDeviceId": video.slaveDeviceId,
                  "startRecordingDate":
                      video.startRecordingDate.toIso8601String(),
                  "endRecordingDate": video.endRecordingDate.toIso8601String(),
                  "receivedDate": video.receivedDate.toIso8601String(),
                  "isUploaded": video.isUploaded,
                })
            .toList(),
      };

      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      LogService.instance
          .registerLog("Session metadata saved to ${metadataFile.path}");
    } catch (e) {
      LogService.instance.registerLog("Error saving session metadata: $e");
    }
  }

  // For loading session metadata
  Future<CaptureSession?> loadSessionMetadata(String sessionGuid) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metadataFile =
          File("${directory.path}/session_$sessionGuid/metadata.json");
      if (!metadataFile.existsSync()) {
        LogService.instance
            .registerLog("No metadata file found for session $sessionGuid");
        return null;
      }

      final metadata = jsonDecode(await metadataFile.readAsString());
      final String deviceId = await DeviceIdService.getOrCreateDeviceId();
      final session = CaptureSession(
        sessionId: metadata["sessionId"],
        sessionGuid: metadata["sessionGuid"] ?? sessionGuid, // Correct if null
        startTime: DateTime.parse(metadata["startTime"]),
        endTime: metadata["endTime"] != null
            ? DateTime.parse(metadata["endTime"])
            : null,
        capturedPhotos: (metadata["photos"] as List<dynamic>).map((photo) {
          return CapturedPhoto(
            photoPath: photo["photoPath"],
            slaveDeviceId: photo["slaveDeviceId"]?.isEmpty ?? true
                ? deviceId
                : photo["slaveDeviceId"],
            captureDate: DateTime.parse(photo["captureDate"]),
            receivedDate: DateTime.parse(photo["receivedDate"]),
            isUploaded: photo["isUploaded"],
          );
        }).toList(),
        capturedVideos: (metadata["videos"] as List<dynamic>).map((video) {
          return CapturedVideo(
            videoPath: video["videoPath"],
            slaveDeviceId: video["slaveDeviceId"]?.isEmpty ?? true
                ? deviceId
                : video["slaveDeviceId"],
            startRecordingDate: DateTime.parse(video["startRecordingDate"]),
            endRecordingDate: DateTime.parse(video["endRecordingDate"]),
            receivedDate: DateTime.parse(video["receivedDate"]),
            isUploaded: video["isUploaded"],
          );
        }).toList(),
      );

      // Correct sessionguid if null
      if (session.sessionGuid == null) {
        session.sessionGuid = sessionGuid;
        await saveSessionMetadata(); // Save updated metadata
        LogService.instance.registerLog(
            "Session GUID was null. Corrected to $sessionGuid and saved.");
      }

      _sessionGuid = metadata["sessionGuid"];
      _deviceType = metadata["deviceType"];

      notifyListeners();

      LogService.instance
          .registerLog("Session metadata loaded for session $sessionGuid");
      return session;
    } catch (e) {
      LogService.instance.registerLog("Error loading session metadata: $e");
      return null;
    }
  }

  // Utility to list past sessions
  Future<List<String>> getAvailableSessions() async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDirs = Directory(directory.path)
        .listSync()
        .where(
            (entity) => entity is Directory && entity.path.contains("session_"))
        .map((entity) => entity.path.split("_").last)
        .toList();

    return sessionDirs;
  }

  /// Method to scan and reconstruct session metadata
  /// Typically used from previous sessions screen
  Future<List<String>> scanAndReconstructSessions() async {
    // store current session if exists
    final previousSession = _currentSession;

    final directory = await getApplicationDocumentsDirectory();
    final sessionDirs = Directory(directory.path)
        .listSync()
        .where(
            (entity) => entity is Directory && entity.path.contains("session_"))
        .toList();

    final List<String> reconstructedSessions = [];

    for (var dir in sessionDirs) {
      final sessionGuid = dir.path.split("_").last;
      final metadataFile = File("${dir.path}/metadata.json");

      try {
        // Skip if metadata already exists
        if (metadataFile.existsSync()) {
          final metadata = jsonDecode(await metadataFile.readAsString());

          // Correct sessionGuid if null
          if (metadata["sessionGuid"] == null) {
            metadata["sessionGuid"] = sessionGuid;
            await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
            LogService.instance.registerLog(
                "Session GUID in metadata was null. Corrected to $sessionGuid and saved.");
          }

          reconstructedSessions.add(sessionGuid);
          continue;
        }

        // If there is no metadata, rebuild
        Directory(dir.path).listSync();

        // Collect photos and videos
        final List<CapturedPhoto> photos = [];
        final List<CapturedVideo> videos = [];
        DateTime? earliestDate;
        final String deviceId = await DeviceIdService.getOrCreateDeviceId();

        for (var entity in Directory(dir.path).listSync()) {
          if (entity is File) {
            final fileStat = await entity.stat();

            // Update the earliest timestamp
            if (earliestDate == null ||
                fileStat.changed.isBefore(earliestDate)) {
              earliestDate = fileStat.changed;
            }

            if (entity.path.endsWith(".jpg")) {
              photos.add(CapturedPhoto(
                photoPath: entity.path,
                slaveDeviceId: deviceId,
                captureDate: fileStat.changed,
                receivedDate: DateTime.now(),
                isUploaded: false,
              ));
            } else if (entity.path.endsWith(".mp4")) {
              videos.add(CapturedVideo(
                videoPath: entity.path,
                slaveDeviceId: deviceId,
                startRecordingDate: fileStat.changed,
                endRecordingDate: fileStat.changed,
                receivedDate: DateTime.now(),
                isUploaded: false,
              ));
            }
          }
        }

        if (photos.isEmpty && videos.isEmpty) {
          LogService.instance.registerLog(
              "No media files found in session directory: $sessionGuid");
          continue;
        }

        // Create session
        final session = CaptureSession(
          sessionId: sessionGuid,
          sessionGuid: sessionGuid,
          startTime: earliestDate ?? DateTime.now(),
          capturedPhotos: photos,
          capturedVideos: videos,
        );

        // Save metadata
        _currentSession = session;
        _sessionGuid = sessionGuid;

        await saveSessionMetadata();
        reconstructedSessions.add(sessionGuid);

        LogService.instance.registerLog(
            "Reconstructed session: $sessionGuid with ${photos.length} photos and ${videos.length} videos.");
      } catch (e) {
        LogService.instance.registerLog(
            "Failed to reconstruct session: $sessionGuid, Error: $e");
      }
    }

    // clean _currentSession with the previous (may be null) one
    _currentSession = previousSession;

    return reconstructedSessions;
  }

  /// Simple method to update current metadata. TODO: Avoid concurrency errors if called at the same time from different parts of the app
  Future<void> updateMetadata() async {
    try {
      if (_currentSession == null || _sessionGuid == null) {
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory(
          "${directory.path}/session_${_currentSession!.sessionGuid}");
      if (!sessionDirectory.existsSync()) {
        sessionDirectory.createSync(recursive: true);
      }

      final metadataFile = File("${sessionDirectory.path}/metadata.json");
      final metadata = {
        "sessionId": _currentSession!.sessionId,
        "sessionGuid": _sessionGuid,
        "startTime": _currentSession!.startTime.toIso8601String(),
        "endTime": _currentSession!.endTime?.toIso8601String(),
        "deviceType": _deviceType,
        "photos": _currentSession!.capturedPhotos
            .map((photo) => {
                  "photoPath": photo.photoPath,
                  "slaveDeviceId": photo.slaveDeviceId,
                  "captureDate": photo.captureDate.toIso8601String(),
                  "receivedDate": photo.receivedDate.toIso8601String(),
                  "isUploaded": photo.isUploaded,
                })
            .toList(),
        "videos": _currentSession!.capturedVideos
            .map((video) => {
                  "videoPath": video.videoPath,
                  "slaveDeviceId": video.slaveDeviceId,
                  "startRecordingDate":
                      video.startRecordingDate.toIso8601String(),
                  "endRecordingDate": video.endRecordingDate.toIso8601String(),
                  "receivedDate": video.receivedDate.toIso8601String(),
                  "isUploaded": video.isUploaded,
                })
            .toList(),
      };

      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      LogService.instance
          .registerLog("Session metadata saved to ${metadataFile.path}");
    } catch (e) {
      LogService.instance.registerLog("Error saving session metadata: $e");
    }
  }
}
