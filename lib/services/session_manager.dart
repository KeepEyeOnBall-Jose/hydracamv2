import "dart:async";
import "dart:collection";
import "dart:convert";
import "package:flutter/foundation.dart";
import "settings_service.dart";
import "uploader_service.dart";
import "package:path_provider/path_provider.dart";
import "../models/capture_context_metadata.dart";
import "../models/capture_session.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "device_service.dart";
import "hydracam_api_service.dart" as api;
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

  bool _isBackendCreated = false;

  final Queue<_SessionMetadataSnapshot> _metadataWriteQueue = Queue();
  bool _isMetadataWriteRunning = false;
  Completer<void>? _metadataWriteIdleCompleter;

  /// Getters for session data
  String? get sessionGuid => _sessionGuid;
  CaptureSession? get currentSession => _currentSession;
  String get deviceType => _deviceType;
  bool get isSessionActive => _currentSession != null;
  bool get isCurrentSessionBackendCreated => _isBackendCreated;
  bool get canUploadCurrentSession =>
      _currentSession != null && _isBackendCreated;

  void startBackendSession(api.HydraCamBackendSession session,
      {required String deviceType}) {
    startSession(
      session.guid,
      session.sessionId,
      deviceType: deviceType,
      backendCreated: true,
    );
  }

  void joinBackendSession(String sessionGuid, String? sessionId,
      {required String deviceType}) {
    startSession(
      sessionGuid,
      sessionId ?? sessionGuid,
      deviceType: deviceType,
      backendCreated: true,
    );
  }

  /// Set the session GUID and initialize a new `CaptureSession`.
  @visibleForTesting
  void startSession(String sessionGuid, String? sessionId,
      {required String deviceType, bool backendCreated = true}) {
    final normalizedSessionGuid = _validateSessionGuid(sessionGuid);
    if (_currentSession != null && _sessionGuid == normalizedSessionGuid) {
      _deviceType = deviceType;
      _isBackendCreated = _isBackendCreated || backendCreated;
      LogService.instance.registerLog(
          "Session already active with GUID: $_sessionGuid. Preserving existing media on rejoin as $_deviceType.");
      notifyListeners();
      return;
    }

    // Reset UploaderService to ensure a clean state for the new session
    UploaderService().reset();

    // Set the session GUID and initialize a new session object
    _sessionGuid = normalizedSessionGuid;
    _deviceType = deviceType;
    _isBackendCreated = backendCreated;
    _currentSession = CaptureSession(
      sessionId: sessionId ?? normalizedSessionGuid,
      sessionGuid: normalizedSessionGuid,
      startTime: DateTime.now(),
      backendCreated: backendCreated,
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
    _isBackendCreated = false;

    // Reset the uploader to clear any pending operations
    UploaderService().reset();

    // Log operation and notify UI
    LogService.instance.registerLog("Session ended and uploader reset.");
    notifyListeners();
  }

  /// Add a captured photo to the current session.
  Future<void> addPhoto(CapturedPhoto photo) async {
    // Add photo to session and notify listeners
    _currentSession?.addPhoto(photo);
    notifyListeners();

    LogService.instance
        .registerLog("Adding photo to upload queue: ${photo.photoPath}");

    // Update metadata
    await updateMetadata();

    // Add photo to uploader queue
    await UploaderService().addMediaToQueue(photo);
  }

  /// Add a captured video to the current session.
  Future<void> addVideo(CapturedVideo video) async {
    // Add video to session and notify listeners
    _currentSession?.addVideo(video);
    notifyListeners();

    LogService.instance
        .registerLog("Adding video to upload queue: ${video.videoPath}");

    // Update metadata
    await updateMetadata();

    // Add video to uploader queue
    await UploaderService().addMediaToQueue(video);
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
  Future<void> saveSessionMetadata() {
    final snapshot = _captureMetadataSnapshot();
    if (snapshot == null) {
      LogService.instance.registerLog(
          "No active session or session GUID is null. Skipping metadata save.");
      return Future<void>.value();
    }
    return _enqueueMetadataWrite(snapshot);
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
      final restoredSessionGuid =
          (metadata["sessionGuid"] ?? sessionGuid).toString();
      final session = CaptureSession(
        sessionId: metadata["sessionId"],
        sessionGuid: restoredSessionGuid, // Correct if null
        startTime: DateTime.parse(metadata["startTime"]),
        endTime: metadata["endTime"] != null
            ? DateTime.parse(metadata["endTime"])
            : null,
        capturedPhotos: (metadata["photos"] as List<dynamic>? ?? const [])
            .map((photo) => _parsePhoto(photo, deviceId))
            .toList(),
        capturedVideos: (metadata["videos"] as List<dynamic>? ?? const [])
            .map((video) => _parseVideo(video, deviceId))
            .toList(),
      );

      // Correct sessionguid if null
      if (session.sessionGuid == null) {
        session.sessionGuid = sessionGuid;
        await saveSessionMetadata(); // Save updated metadata
        LogService.instance.registerLog(
            "Session GUID was null. Corrected to $sessionGuid and saved.");
      }

      _sessionGuid = restoredSessionGuid;
      _deviceType = metadata["deviceType"] ?? "Unknown";
      _isBackendCreated = _metadataMarksBackendCreated(
        metadata,
        restoredSessionGuid,
      );

      notifyListeners();

      LogService.instance
          .registerLog("Session metadata loaded for session $sessionGuid");
      return session;
    } catch (e) {
      LogService.instance.registerLog("Error loading session metadata: $e");
      return null;
    }
  }

  Future<CaptureSession?> loadSessionMetadataSnapshot(
      String sessionGuid) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metadataFile =
          File("${directory.path}/session_$sessionGuid/metadata.json");
      if (!metadataFile.existsSync()) {
        LogService.instance.registerLog(
            "No metadata file found for session snapshot $sessionGuid");
        return null;
      }

      final metadata = jsonDecode(await metadataFile.readAsString());
      final String deviceId = await DeviceIdService.getOrCreateDeviceId();
      final session = CaptureSession(
        sessionId: metadata["sessionId"],
        sessionGuid: metadata["sessionGuid"] ?? sessionGuid,
        startTime: DateTime.parse(metadata["startTime"]),
        endTime: metadata["endTime"] != null
            ? DateTime.parse(metadata["endTime"])
            : null,
        capturedPhotos: (metadata["photos"] as List<dynamic>? ?? const [])
            .map((photo) => _parsePhoto(photo, deviceId))
            .toList(),
        capturedVideos: (metadata["videos"] as List<dynamic>? ?? const [])
            .map((video) => _parseVideo(video, deviceId))
            .toList(),
      );

      LogService.instance
          .registerLog("Session metadata snapshot loaded for $sessionGuid");
      return session;
    } catch (e) {
      LogService.instance
          .registerLog("Error loading session metadata snapshot: $e");
      return null;
    }
  }

  Future<CaptureSession> restoreSessionFromMetadata(
    String sessionIdentifier, {
    required String deviceType,
  }) async {
    final loadedSession = await loadSessionMetadataSnapshot(sessionIdentifier);
    if (loadedSession == null) {
      throw Exception(
          "Failed to load session metadata for session: $sessionIdentifier");
    }

    final restoredSessionGuid = loadedSession.sessionGuid ?? sessionIdentifier;
    final backendCreated =
        await _metadataSessionIsBackendCreated(sessionIdentifier);
    if (!backendCreated) {
      throw StateError(
          "Stored session $restoredSessionGuid is not backend-created and cannot be restored for upload.");
    }
    startSession(
      restoredSessionGuid,
      loadedSession.sessionId,
      deviceType: deviceType,
      backendCreated: true,
    );

    for (final photo in loadedSession.capturedPhotos) {
      await addPhoto(photo);
    }
    for (final video in loadedSession.capturedVideos) {
      await addVideo(video);
    }

    return loadedSession;
  }

  // Utility to list past sessions
  Future<List<String>> getAvailableSessions() async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDirs = Directory(directory.path)
        .listSync()
        .where((entity) =>
            entity is Directory && _entityName(entity).startsWith("session_"))
        .map(_sessionIdentifierFromDirectory)
        .toList();

    return sessionDirs;
  }

  /// Method to scan and reconstruct session metadata
  /// Typically used from previous sessions screen
  Future<List<String>> scanAndReconstructSessions() async {
    // store current session if exists
    final previousSession = _currentSession;
    final previousSessionGuid = _sessionGuid;
    final previousDeviceType = _deviceType;
    final previousBackendCreated = _isBackendCreated;

    final directory = await getApplicationDocumentsDirectory();
    final sessionDirs = Directory(directory.path)
        .listSync()
        .where((entity) =>
            entity is Directory && _entityName(entity).startsWith("session_"))
        .toList();

    final List<String> reconstructedSessions = [];

    for (var dir in sessionDirs) {
      final sessionGuid = _sessionIdentifierFromDirectory(dir);
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
          metadata["backendCreated"] = _metadataMarksBackendCreated(
            metadata,
            sessionGuid,
          );
          await metadataFile.writeAsString(jsonEncode(metadata), flush: true);

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
        _isBackendCreated = false;

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
    _sessionGuid = previousSessionGuid;
    _deviceType = previousDeviceType;
    _isBackendCreated = previousBackendCreated;

    return reconstructedSessions;
  }

  String _entityName(FileSystemEntity entity) {
    return entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
  }

  String _sessionIdentifierFromDirectory(FileSystemEntity entity) {
    return _entityName(entity).replaceFirst("session_", "");
  }

  /// Writes a captured snapshot of the current metadata in FIFO order.
  Future<void> updateMetadata() {
    final snapshot = _captureMetadataSnapshot();
    if (snapshot == null) {
      return Future<void>.value();
    }
    return _enqueueMetadataWrite(snapshot);
  }

  _SessionMetadataSnapshot? _captureMetadataSnapshot() {
    if (_currentSession == null || _sessionGuid == null) {
      return null;
    }
    return _SessionMetadataSnapshot(
      sessionDirectoryGuid: _currentSession!.sessionGuid ?? _sessionGuid!,
      metadata: _buildMetadataJson(),
    );
  }

  Future<void> _enqueueMetadataWrite(_SessionMetadataSnapshot snapshot) {
    _metadataWriteQueue.add(snapshot);
    _metadataWriteIdleCompleter ??= Completer<void>();
    if (!_isMetadataWriteRunning) {
      unawaited(_drainMetadataWriteQueue());
    }
    return _metadataWriteIdleCompleter!.future;
  }

  Future<void> _drainMetadataWriteQueue() async {
    _isMetadataWriteRunning = true;
    try {
      while (_metadataWriteQueue.isNotEmpty) {
        await _writeMetadataSnapshot(_metadataWriteQueue.removeFirst());
      }
    } finally {
      _isMetadataWriteRunning = false;
      final idleCompleter = _metadataWriteIdleCompleter;
      _metadataWriteIdleCompleter = null;
      if (idleCompleter != null && !idleCompleter.isCompleted) {
        idleCompleter.complete();
      }
    }
  }

  Future<void> _writeMetadataSnapshot(_SessionMetadataSnapshot snapshot) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sessionDirectory = Directory(
          "${directory.path}/session_${snapshot.sessionDirectoryGuid}");
      if (!sessionDirectory.existsSync()) {
        sessionDirectory.createSync(recursive: true);
      }

      final metadataFile = File("${sessionDirectory.path}/metadata.json");

      await metadataFile.writeAsString(
        jsonEncode(snapshot.metadata),
        flush: true,
      );
      LogService.instance
          .registerLog("Session metadata saved to ${metadataFile.path}");
    } catch (e) {
      LogService.instance.registerLog("Error saving session metadata: $e");
    }
  }

  Map<String, dynamic> _buildMetadataJson() {
    return {
      "sessionId": _currentSession!.sessionId,
      "sessionGuid": _sessionGuid,
      "backendCreated": _isBackendCreated,
      "startTime": _currentSession!.startTime.toIso8601String(),
      "endTime": _currentSession!.endTime?.toIso8601String(),
      "deviceType": _deviceType,
      "photos": _currentSession!.capturedPhotos.map(_photoToJson).toList(),
      "videos": _currentSession!.capturedVideos.map(_videoToJson).toList(),
    };
  }

  Map<String, dynamic> _photoToJson(CapturedPhoto photo) {
    return {
      "photoPath": photo.photoPath,
      "slaveDeviceId": photo.slaveDeviceId,
      "captureDate": photo.captureDate.toIso8601String(),
      "receivedDate": photo.receivedDate.toIso8601String(),
      "isUploaded": photo.isUploaded,
      if (photo.uploadFailureReason != null)
        "uploadFailureReason": photo.uploadFailureReason,
      if (photo.captureContext != null)
        "captureContext": photo.captureContext!.toJson(),
    };
  }

  Map<String, dynamic> _videoToJson(CapturedVideo video) {
    return {
      "videoPath": video.videoPath,
      "slaveDeviceId": video.slaveDeviceId,
      "startRecordingDate": video.startRecordingDate.toIso8601String(),
      "endRecordingDate": video.endRecordingDate.toIso8601String(),
      "receivedDate": video.receivedDate.toIso8601String(),
      "isUploaded": video.isUploaded,
      if (video.uploadFailureReason != null)
        "uploadFailureReason": video.uploadFailureReason,
      if (video.captureContext != null)
        "captureContext": video.captureContext!.toJson(),
    };
  }

  CapturedPhoto _parsePhoto(Object? rawPhoto, String fallbackDeviceId) {
    final photo = _asMap(rawPhoto);
    final slaveDeviceId = photo["slaveDeviceId"]?.toString();
    return CapturedPhoto(
      photoPath: photo["photoPath"].toString(),
      slaveDeviceId: slaveDeviceId == null || slaveDeviceId.isEmpty
          ? fallbackDeviceId
          : slaveDeviceId,
      captureDate: DateTime.parse(photo["captureDate"].toString()),
      receivedDate: DateTime.parse(photo["receivedDate"].toString()),
      isUploaded: photo["isUploaded"] == true,
      uploadFailureReason: photo["uploadFailureReason"]?.toString(),
      captureContext:
          MediaCaptureContext.fromJson(_asNullableMap(photo["captureContext"])),
    );
  }

  CapturedVideo _parseVideo(Object? rawVideo, String fallbackDeviceId) {
    final video = _asMap(rawVideo);
    final slaveDeviceId = video["slaveDeviceId"]?.toString();
    return CapturedVideo(
      videoPath: video["videoPath"].toString(),
      slaveDeviceId: slaveDeviceId == null || slaveDeviceId.isEmpty
          ? fallbackDeviceId
          : slaveDeviceId,
      startRecordingDate:
          DateTime.parse(video["startRecordingDate"].toString()),
      endRecordingDate: DateTime.parse(video["endRecordingDate"].toString()),
      receivedDate: DateTime.parse(video["receivedDate"].toString()),
      isUploaded: video["isUploaded"] == true,
      uploadFailureReason: video["uploadFailureReason"]?.toString(),
      captureContext:
          MediaCaptureContext.fromJson(_asNullableMap(video["captureContext"])),
    );
  }

  String _validateSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    if (normalizedSessionGuid.isEmpty) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "Backend session GUID is required.",
      );
    }
    if (normalizedSessionGuid.startsWith("local-")) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "Local sessions are not uploadable; create or join a backend session first.",
      );
    }
    return normalizedSessionGuid;
  }

  Future<bool> _metadataSessionIsBackendCreated(String sessionGuid) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final metadataFile =
          File("${directory.path}/session_$sessionGuid/metadata.json");
      if (!metadataFile.existsSync()) {
        return _looksLikeBackendSessionGuid(sessionGuid);
      }
      final metadata = _asMap(jsonDecode(await metadataFile.readAsString()));
      return _metadataMarksBackendCreated(metadata, sessionGuid);
    } catch (e) {
      LogService.instance.registerLog(
          "Failed to inspect backend-created metadata for $sessionGuid: $e");
      return false;
    }
  }

  bool _metadataMarksBackendCreated(
    Map<String, dynamic> metadata,
    String fallbackSessionGuid,
  ) {
    final sessionGuid =
        (metadata["sessionGuid"] ?? fallbackSessionGuid).toString();
    if (!_looksLikeBackendSessionGuid(sessionGuid)) {
      return false;
    }
    final explicitBackendCreated = metadata["backendCreated"];
    if (explicitBackendCreated is bool) {
      return explicitBackendCreated;
    }
    return true;
  }

  bool _looksLikeBackendSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    return normalizedSessionGuid.isNotEmpty &&
        !normalizedSessionGuid.startsWith("local-");
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic>? _asNullableMap(Object? value) {
    if (value == null) {
      return null;
    }
    return _asMap(value);
  }
}

class _SessionMetadataSnapshot {
  const _SessionMetadataSnapshot({
    required this.sessionDirectoryGuid,
    required this.metadata,
  });

  final String sessionDirectoryGuid;
  final Map<String, dynamic> metadata;
}
