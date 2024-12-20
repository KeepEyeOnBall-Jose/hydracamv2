import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hydracam/services/settings_service.dart';
import 'package:hydracam/services/uploader_service.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Lock for updating metadata.json
  final Completer<void> _metadataUpdateLock = Completer<void>()..complete();


  /// Set the session GUID and initialize a new `CaptureSession`.
  void startSession(String sessionGuid, {required String deviceType}) {

    // Reset UploaderService to ensure a clean state for the new session
    UploaderService().reset();

    // Set the session GUID and initialize a new session object
    _sessionGuid = sessionGuid;
    _deviceType = deviceType;
    _currentSession = CaptureSession(
      sessionId: sessionGuid,
      startTime: DateTime.now(),
    );

    // Log session start and notify listeners
    LogService.instance.registerLog("Session started with GUID: $_sessionGuid on device type: $_deviceType");
    notifyListeners();
  }

  /// Ends the current session, clearing data.
  void endSession() async {

    if (_currentSession == null) {
      LogService.instance.registerLog("No active session to end.");
      return;
    }

    // End current session
    _currentSession?.endSession();
    // Update metadata.json file
    await _safeUpdateMetadata();
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

    LogService.instance.registerLog("Adding photo to upload queue: ${photo.photoPath}");

    // Update metadata
    _safeUpdateMetadata();

    // Add photo to uploader queue
    UploaderService().addMediaToQueue(photo);

  }

  /// Add a captured video to the current session.
  void addVideo(CapturedVideo video) {

    // Add video to session and notify listeners
    _currentSession?.addVideo(video);
    notifyListeners();

    LogService.instance.registerLog("Adding video to upload queue: ${video.videoPath}");

    // Update metadata
    _safeUpdateMetadata();

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

  /// --------------------------------
  /// METHODS FOR PERSISTENT SESSIONS
  /// --------------------------------

  // For writing session metadata
  Future<void> saveSessionMetadata() async {
    if (_currentSession == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory('${directory.path}/session_${_currentSession!.sessionId}');
      if (!sessionDirectory.existsSync()) {
        sessionDirectory.createSync(recursive: true);
      }

      final metadataFile = File('${sessionDirectory.path}/metadata.json');
      final metadata = {
        'sessionId': _currentSession!.sessionId,
        'sessionGuid': _sessionGuid,
        'startTime': _currentSession!.startTime.toIso8601String(),
        'endTime': _currentSession!.endTime?.toIso8601String(),
        'deviceType': _deviceType,
        'photos': _currentSession!.capturedPhotos.map((photo) => {
          'photoPath': photo.photoPath,
          'captureDate': photo.captureDate.toIso8601String(),
          'receivedDate': photo.receivedDate.toIso8601String(),
          'isUploaded': photo.isUploaded,
        }).toList(),
        'videos': _currentSession!.capturedVideos.map((video) => {
          'videoPath': video.videoPath,
          'startRecordingDate': video.startRecordingDate.toIso8601String(),
          'endRecordingDate': video.endRecordingDate.toIso8601String(),
          'receivedDate': video.receivedDate.toIso8601String(),
          'isUploaded': video.isUploaded,
        }).toList(),
      };

      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      LogService.instance.registerLog("Session metadata saved to ${metadataFile.path}");
    } catch (e) {
      LogService.instance.registerLog("Error saving session metadata: $e");
    }
  }

  // For loading session metadata
  Future<CaptureSession?> loadSessionMetadata(String sessionId) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metadataFile = File('${directory.path}/session_$sessionId/metadata.json');
      if (!metadataFile.existsSync()) {
        LogService.instance.registerLog("No metadata file found for session $sessionId");
        return null;
      }

      final metadata = jsonDecode(await metadataFile.readAsString());
      final session = CaptureSession(
        sessionId: metadata['sessionId'],
        startTime: DateTime.parse(metadata['startTime']),
        endTime: metadata['endTime'] != null ? DateTime.parse(metadata['endTime']) : null,
        capturedPhotos: (metadata['photos'] as List<dynamic>).map((photo) {
          return CapturedPhoto(
            photoPath: photo['photoPath'],
            slaveDeviceId: "", // Placeholder, as device ID may not be stored
            captureDate: DateTime.parse(photo['captureDate']),
            receivedDate: DateTime.parse(photo['receivedDate']),
            isUploaded: photo['isUploaded'],
          );
        }).toList(),
        capturedVideos: (metadata['videos'] as List<dynamic>).map((video) {
          return CapturedVideo(
            videoPath: video['videoPath'],
            slaveDeviceId: "", // Placeholder
            startRecordingDate: DateTime.parse(video['startRecordingDate']),
            endRecordingDate: DateTime.parse(video['endRecordingDate']),
            receivedDate: DateTime.parse(video['receivedDate']),
            isUploaded: video['isUploaded'],
          );
        }).toList(),
      );

      _sessionGuid = metadata['sessionGuid'];
      _deviceType = metadata['deviceType'];
      LogService.instance.registerLog("Session metadata loaded for session $sessionId");
      return session;
    } catch (e) {
      LogService.instance.registerLog("Error loading session metadata: $e");
      return null;
    }
  }

  // Utility to list past sessions
  Future<List<String>> getAvailableSessions() async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDirs = Directory(directory.path).listSync()
        .where((entity) => entity is Directory && entity.path.contains('session_'))
        .map((entity) => entity.path.split('_').last)
        .toList();

    return sessionDirs;
  }

  /// Method to scan and reconstruct session metadata
  /// Typically used from previous sessions screen
  Future<List<String>> scanAndReconstructSessions() async {

    // store current session if exists
    var previousSession = _currentSession;


    final directory = await getApplicationDocumentsDirectory();
    print("Scanning directory: ${directory.path}");
    final sessionDirs = Directory(directory.path)
        .listSync()
        .where((entity) => entity is Directory && entity.path.contains('session_'))
        .toList();

    print("Found directories: ${sessionDirs.map((e) => e.path).toList()}");
    List<String> reconstructedSessions = [];

    for (var dir in sessionDirs) {
      print("Checking directory: ${dir.path}");
      final sessionId = dir.path.split('_').last;
      final metadataFile = File('${dir.path}/metadata.json');

      // Skip if metadata already exists
      if (metadataFile.existsSync()) {
        LogService.instance.registerLog("Metadata already exists for session: $sessionId");
        continue;
      }

      try {
        print("Scanning contents of directory: ${dir.path}");
        final directoryContents = Directory(dir.path).listSync();
        print("Contents: ${directoryContents.map((e) => e.path).toList()}");

        // Collect photos and videos
        List<CapturedPhoto> photos = [];
        List<CapturedVideo> videos = [];
        DateTime? earliestDate;

        for (var entity in Directory(dir.path).listSync()) {
          if (entity is File) {
            final fileStat = await entity.stat();

            // Update the earliest timestamp
            if (earliestDate == null || fileStat.changed.isBefore(earliestDate)) {
              earliestDate = fileStat.changed;
            }

            if (entity.path.endsWith('.jpg')) {
              print("Found photo: ${entity.path}");
              photos.add(CapturedPhoto(
                photoPath: entity.path,
                slaveDeviceId: "", // Placeholder
                captureDate: fileStat.changed,
                receivedDate: DateTime.now(),
                isUploaded: false,
              ));
            } else if (entity.path.endsWith('.mp4')) {
              videos.add(CapturedVideo(
                videoPath: entity.path,
                slaveDeviceId: "", // Placeholder
                startRecordingDate: fileStat.changed,
                endRecordingDate: fileStat.changed,
                receivedDate: DateTime.now(),
                isUploaded: false,
              ));
            }
          }
        }

        if (photos.isEmpty && videos.isEmpty) {
          LogService.instance.registerLog("No media files found in session directory: $sessionId");
          continue;
        }

        // Create session
        final session = CaptureSession(
          sessionId: sessionId,
          startTime: earliestDate ?? DateTime.now(),
          capturedPhotos: photos,
          capturedVideos: videos,
        );

        // Save metadata
        _currentSession = session;
        await saveSessionMetadata();
        reconstructedSessions.add(sessionId);

        LogService.instance.registerLog("Reconstructed session: $sessionId with ${photos.length} photos and ${videos.length} videos.");
      } catch (e) {
        LogService.instance.registerLog("Failed to reconstruct session: $sessionId, Error: $e");
      }
    }

    // clean _currentSession with the previous (may be null) one
    _currentSession = previousSession;

    return reconstructedSessions;
  }

  /// Method to safely update metadata.json, without concurrency errors
  Future<void> _safeUpdateMetadata() async {
    // Enqueue the task in the metadata update lock
    final previousTask = _metadataUpdateLock.future;
    final newTask = Completer<void>();

    _metadataUpdateLock.complete(newTask.future);

    await previousTask; // Wait until previous update is finished
    try {
      if (_currentSession == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory('${directory.path}/session_${_currentSession!.sessionId}');
      if (!sessionDirectory.existsSync()) {
        sessionDirectory.createSync(recursive: true);
      }

      final metadataFile = File('${sessionDirectory.path}/metadata.json');
      final metadata = {
        'sessionId': _currentSession!.sessionId,
        'sessionGuid': _sessionGuid,
        'startTime': _currentSession!.startTime.toIso8601String(),
        'endTime': _currentSession!.endTime?.toIso8601String(),
        'deviceType': _deviceType,
        'photos': _currentSession!.capturedPhotos.map((photo) => {
          'photoPath': photo.photoPath,
          'captureDate': photo.captureDate.toIso8601String(),
          'receivedDate': photo.receivedDate.toIso8601String(),
          'isUploaded': photo.isUploaded,
        }).toList(),
        'videos': _currentSession!.capturedVideos.map((video) => {
          'videoPath': video.videoPath,
          'startRecordingDate': video.startRecordingDate.toIso8601String(),
          'endRecordingDate': video.endRecordingDate.toIso8601String(),
          'receivedDate': video.receivedDate.toIso8601String(),
          'isUploaded': video.isUploaded,
        }).toList(),
      };

      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      LogService.instance.registerLog("Session metadata updated at ${metadataFile.path}");
    } catch (e) {
      LogService.instance.registerLog("Error updating session metadata: $e");
    } finally {
      newTask.complete(); // Mark task as completed!
    }
  }

  /// Public method to safely update the metadata
  Future<void> safeUpdateMetadata() async {
    await _safeUpdateMetadata();
  }



}
