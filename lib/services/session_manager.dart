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
import "../models/sync_metadata.dart";
import "debug_session_policy.dart";
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

  final DebugSessionPolicy _debugSessionPolicy = DebugSessionPolicy();

  /// The unique identifier for the current session (GUID).
  String? _sessionGuid;

  /// The `CaptureSession` object for tracking media in the current session.
  CaptureSession? _currentSession;

  /// The type of device (Master or Slave) for this instance.
  String _deviceType = "Unknown";

  final Queue<_SessionMetadataSnapshot> _metadataWriteQueue = Queue();
  bool _isMetadataWriteRunning = false;
  Completer<void>? _metadataWriteIdleCompleter;

  /// Getters for session data
  String? get sessionGuid => _sessionGuid;
  CaptureSession? get currentSession => _currentSession;
  String get deviceType => _deviceType;
  bool get isSessionActive => _currentSession != null;
  bool get canUploadCurrentSession =>
      _currentSession != null && isServiceSessionGuid(_sessionGuid);
  bool get isCurrentSessionDebug => _currentSession?.debugSession ?? false;

  static bool isServiceSessionGuid(String? sessionGuid) {
    final normalizedSessionGuid = sessionGuid?.trim() ?? "";
    return normalizedSessionGuid.isNotEmpty &&
        !normalizedSessionGuid.startsWith("local-");
  }

  void startCreatedSession(
    api.HydraCamBackendSession session, {
    required String deviceType,
    bool debugSession = false,
  }) {
    startSession(
      session.guid,
      session.sessionId,
      deviceType: deviceType,
      debugSession: debugSession,
      serviceNumericId: session.numericId,
    );
  }

  void joinSession(
    String sessionGuid,
    String? sessionId, {
    required String deviceType,
    bool debugSession = false,
    int? serviceNumericId,
  }) {
    startSession(
      sessionGuid,
      sessionId ?? sessionGuid,
      deviceType: deviceType,
      debugSession: debugSession,
      serviceNumericId: serviceNumericId,
    );
  }

  /// Set the session GUID and initialize a new `CaptureSession`.
  @visibleForTesting
  void startSession(
    String sessionGuid,
    String? sessionId, {
    required String deviceType,
    bool debugSession = false,
    int? serviceNumericId,
  }) {
    final normalizedSessionGuid = _validateServiceSessionGuid(sessionGuid);
    if (_currentSession != null && _sessionGuid == normalizedSessionGuid) {
      _deviceType = deviceType;
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
    _currentSession = CaptureSession(
      sessionId: sessionId ?? normalizedSessionGuid,
      sessionGuid: normalizedSessionGuid,
      startTime: DateTime.now(),
      debugSession: debugSession,
      serviceNumericId: serviceNumericId,
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
  Future<void> addPhoto(CapturedPhoto photo) async {
    // Add photo to session and notify listeners
    _currentSession?.addPhoto(photo);
    notifyListeners();

    LogService.instance
        .registerLog("Adding photo to upload queue: ${photo.photoPath}");

    // Update metadata
    await updateMetadata();

    // Write the per-clip sync sidecar so a later import tool can align media.
    if (photo.syncMetadata != null) {
      await _writeSyncSidecar(photo.photoPath, {
        "mediaPath": photo.photoPath,
        "deviceId": photo.slaveDeviceId,
        "captureDate": photo.captureDate.toIso8601String(),
        "sessionGuid": _sessionGuid,
        "sync": photo.syncMetadata!.toJson(),
      });
    }

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

    // Write the per-clip sync sidecar so a later import tool can align media.
    if (video.syncMetadata != null) {
      await _writeSyncSidecar(video.videoPath, {
        "mediaPath": video.videoPath,
        "deviceId": video.slaveDeviceId,
        "startRecordingDate": video.startRecordingDate.toIso8601String(),
        "endRecordingDate": video.endRecordingDate.toIso8601String(),
        "sessionGuid": _sessionGuid,
        "sync": video.syncMetadata!.toJson(),
      });
    }

    // Add video to uploader queue
    await UploaderService().addMediaToQueue(video);
  }

  /// Deletes a file if the setting to delete local files is enabled.
  Future<void> deleteFileIfAllowed(String filePath) async {
    final shouldDelete = await shouldDeleteUploadedFile();
    if (!shouldDelete) {
      return;
    }
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
        LogService.instance
            .registerLog("Deleted uploaded local file: $filePath");
      } catch (e) {
        LogService.instance.registerLog(
            "Failed to delete uploaded local file: $filePath, error: $e");
      }
    } else {
      LogService.instance
          .registerLog("Uploaded local file already missing: $filePath");
    }
  }

  Future<bool> shouldDeleteUploadedFile() async {
    if (_debugSessionPolicy.shouldDeleteUploadedLocalMedia(
      debugSession: isCurrentSessionDebug,
    )) {
      return true;
    }
    return SettingsService.getDeleteLocalAfterUpload();
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

  // For previewing stored session metadata without changing the active session.
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

      final metadata = _asMap(jsonDecode(await metadataFile.readAsString()));
      final String deviceId = await DeviceIdService.getOrCreateDeviceId();
      final restoredSessionGuid = await _normalizedStoredSessionGuid(
          metadataFile, metadata, sessionGuid);
      final session = CaptureSession(
        sessionId: metadata["sessionId"],
        sessionGuid: restoredSessionGuid,
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
        debugSession: metadata["debugSession"] == true,
        serviceNumericId: _asNullableInt(metadata["serviceNumericId"]),
      );

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

      final metadata = _asMap(jsonDecode(await metadataFile.readAsString()));
      final String deviceId = await DeviceIdService.getOrCreateDeviceId();
      final restoredSessionGuid = await _normalizedStoredSessionGuid(
          metadataFile, metadata, sessionGuid);
      final session = CaptureSession(
        sessionId: metadata["sessionId"],
        sessionGuid: restoredSessionGuid,
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
        debugSession: metadata["debugSession"] == true,
        serviceNumericId: _asNullableInt(metadata["serviceNumericId"]),
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

    final restoredSessionGuid =
        loadedSession.sessionGuid?.trim().isNotEmpty == true
            ? loadedSession.sessionGuid!.trim()
            : sessionIdentifier;
    if (!isServiceSessionGuid(restoredSessionGuid)) {
      throw StateError(
          "Stored media $restoredSessionGuid is not attached to a service session and cannot be restored for upload.");
    }
    startSession(
      restoredSessionGuid,
      loadedSession.sessionId,
      deviceType: deviceType,
      debugSession: loadedSession.debugSession,
      serviceNumericId: loadedSession.serviceNumericId,
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
        .where(isServiceSessionGuid)
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
        if (!isServiceSessionGuid(sessionGuid)) {
          LogService.instance.registerLog(
              "Skipping legacy device media folder while scanning service sessions: $sessionGuid");
          continue;
        }

        // Skip if metadata already exists
        if (metadataFile.existsSync()) {
          final metadata = jsonDecode(await metadataFile.readAsString());
          await _normalizedStoredSessionGuid(metadataFile, metadata, sessionGuid);
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

  /// Writes a `<mediaPath>.sync.json` sidecar next to a captured media file.
  /// This is the per-clip sync contract from the spec; `metadata.json` remains
  /// the in-app source of truth.
  Future<void> _writeSyncSidecar(
      String mediaPath, Map<String, dynamic> payload) async {
    try {
      final sidecar = File("$mediaPath.sync.json");
      await sidecar.writeAsString(jsonEncode(payload), flush: true);
      LogService.instance.registerLog("Sync sidecar saved to ${sidecar.path}");
    } catch (e) {
      LogService.instance.registerLog("Error saving sync sidecar: $e");
    }
  }

  Map<String, dynamic> _buildMetadataJson() {
    return {
      "sessionId": _currentSession!.sessionId,
      "sessionGuid": _sessionGuid,
      "debugSession": _currentSession!.debugSession,
      "serviceNumericId": _currentSession!.serviceNumericId,
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
      "fileSizeInBytes": photo.fileSizeInBytes,
      if (photo.uploadFailureReason != null)
        "uploadFailureReason": photo.uploadFailureReason,
      if (photo.captureContext != null)
        "captureContext": photo.captureContext!.toJson(),
      if (photo.syncMetadata != null)
        "syncMetadata": photo.syncMetadata!.toJson(),
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
      "fileSizeInBytes": video.fileSizeInBytes,
      if (video.uploadFailureReason != null)
        "uploadFailureReason": video.uploadFailureReason,
      if (video.captureContext != null)
        "captureContext": video.captureContext!.toJson(),
      if (video.syncMetadata != null)
        "syncMetadata": video.syncMetadata!.toJson(),
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
      fileSizeInBytes: _asNullableInt(photo["fileSizeInBytes"]),
      captureContext:
          MediaCaptureContext.fromJson(_asNullableMap(photo["captureContext"])),
      syncMetadata: SyncMetadata.fromJson(photo["syncMetadata"]),
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
      fileSizeInBytes: _asNullableInt(video["fileSizeInBytes"]),
      captureContext:
          MediaCaptureContext.fromJson(_asNullableMap(video["captureContext"])),
      syncMetadata: SyncMetadata.fromJson(video["syncMetadata"]),
    );
  }

  String _validateServiceSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    if (normalizedSessionGuid.isEmpty) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "Service session GUID is required.",
      );
    }
    if (!isServiceSessionGuid(normalizedSessionGuid)) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "A service-created session is required before capture or upload.",
      );
    }
    return normalizedSessionGuid;
  }

  Future<String> _normalizedStoredSessionGuid(
    File metadataFile,
    Map<String, dynamic> metadata,
    String storageIdentifier,
  ) async {
    final fallbackGuid = storageIdentifier.trim();
    final rawSessionGuid = metadata["sessionGuid"]?.toString();
    final normalizedSessionGuid = rawSessionGuid?.trim();
    final repairedSessionGuid = normalizedSessionGuid?.isNotEmpty == true
        ? normalizedSessionGuid!
        : fallbackGuid;

    if (rawSessionGuid != repairedSessionGuid) {
      metadata["sessionGuid"] = repairedSessionGuid;
      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      LogService.instance.registerLog(
          "Stored session GUID repaired to $repairedSessionGuid for $storageIdentifier.");
    }

    return repairedSessionGuid;
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

  int? _asNullableInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
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
