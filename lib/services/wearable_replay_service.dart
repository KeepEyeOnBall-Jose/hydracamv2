import "dart:convert";
import "dart:io";

import "package:path_provider/path_provider.dart";

import "../models/wearable_replay.dart";
import "log_service.dart";
import "session_manager.dart";
import "session_media_storage.dart";

class WearableReplayService {
  WearableReplayService({
    SessionManager? sessionManager,
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    DateTime Function()? now,
    int maxSamplesPerChunk = 300,
  })  : _sessionManager = sessionManager ?? SessionManager.instance,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _now = now ?? DateTime.now,
        _maxSamplesPerChunk = maxSamplesPerChunk;

  final SessionManager _sessionManager;
  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final DateTime Function() _now;
  final int _maxSamplesPerChunk;
  final Map<String, int> _sampleCountsByTrack = {};

  Future<File> recordTrack(WearableTrack track) async {
    final sessionDirectory = await _requireSessionDirectory(track.sessionGuid);
    final file = File(
      "${sessionDirectory.path}/wearables/tracks/${track.trackId}.json",
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(track.toJson()), flush: true);
    LogService.instance.registerLog(
      "Wearable replay track saved to ${file.path}",
    );
    return file;
  }

  Future<File> appendSample(WearableSample sample) async {
    final sessionDirectory =
        await _requireSessionDirectory(sample.context.sessionGuid);
    final sampleIndex = _sampleCountsByTrack[sample.trackId] ?? 0;
    final chunkIndex = sampleIndex ~/ _maxSamplesPerChunk;
    _sampleCountsByTrack[sample.trackId] = sampleIndex + 1;

    final file = File(
      "${sessionDirectory.path}/wearables/samples/"
      "${sample.trackId}-chunk-${chunkIndex.toString().padLeft(4, "0")}.jsonl",
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      "${jsonEncode(sample.toJson())}\n",
      mode: FileMode.append,
      flush: true,
    );
    return file;
  }

  Future<File> recordMarker(WearableMarker marker) async {
    final sessionDirectory =
        await _requireSessionDirectory(marker.context.sessionGuid);
    return _writeJsonFile(
      File(
        "${sessionDirectory.path}/wearables/markers/${marker.markerId}.json",
      ),
      marker.toJson(),
      logLabel: "Wearable replay marker",
    );
  }

  Future<File> recordSyncCalibration(
    WearableSyncCalibration calibration,
  ) async {
    final sessionDirectory =
        await _requireSessionDirectory(calibration.context.sessionGuid);
    return _writeJsonFile(
      File(
        "${sessionDirectory.path}/wearables/calibration/"
        "${calibration.calibrationId}.json",
      ),
      calibration.toJson(),
      logLabel: "Wearable replay sync calibration",
    );
  }

  Future<File> recordPovRecording(PovRecording recording) async {
    final sessionDirectory =
        await _requireSessionDirectory(recording.context.sessionGuid);
    final payload = recording.toJson();
    final stagedMediaFile = await _stagePovMediaFile(
      sessionDirectory,
      recording.mediaPath,
      recording.recordingId,
    );
    if (stagedMediaFile != null) {
      payload["originalMediaPath"] = recording.mediaPath;
      payload["mediaPath"] = stagedMediaFile.path;
    }
    return _writeJsonFile(
      File(
        "${sessionDirectory.path}/wearables/pov/"
        "${recording.recordingId}.json",
      ),
      payload,
      logLabel: "Wearable replay POV recording",
    );
  }

  Future<File> recordFeedbackEvent(FeedbackEvent event) async {
    final sessionDirectory =
        await _requireSessionDirectory(event.context.sessionGuid);
    return _writeJsonFile(
      File(
        "${sessionDirectory.path}/wearables/feedback/"
        "${event.feedbackId}.json",
      ),
      event.toJson(),
      logLabel: "Wearable replay feedback event",
    );
  }

  Future<File> writeUploadManifest(String sessionGuid) async {
    final sessionDirectory = await _requireSessionDirectory(sessionGuid);
    final povRecordingFiles =
        await _filePathsIn("${sessionDirectory.path}/wearables/pov");
    final manifest = WearableReplayUploadManifest(
      sessionGuid: sessionGuid,
      generatedAt: _now(),
      trackFiles:
          await _filePathsIn("${sessionDirectory.path}/wearables/tracks"),
      sampleFiles:
          await _filePathsIn("${sessionDirectory.path}/wearables/samples"),
      calibrationFiles: await _filePathsIn(
        "${sessionDirectory.path}/wearables/calibration",
      ),
      markerFiles:
          await _filePathsIn("${sessionDirectory.path}/wearables/markers"),
      povRecordingFiles: povRecordingFiles,
      povMediaFiles: await _povMediaPathsFrom(povRecordingFiles),
      feedbackFiles:
          await _filePathsIn("${sessionDirectory.path}/wearables/feedback"),
    );
    return _writeJsonFile(
      File("${sessionDirectory.path}/wearables/wearable-upload-manifest.json"),
      manifest.toJson(),
      logLabel: "Wearable replay upload manifest",
    );
  }

  Future<Directory> _requireSessionDirectory(String recordSessionGuid) async {
    final activeSessionGuid = _sessionManager.sessionGuid?.trim();
    if (!_sessionManager.isSessionActive ||
        activeSessionGuid == null ||
        activeSessionGuid.isEmpty) {
      throw StateError("No active session available for wearable replay data.");
    }
    if (recordSessionGuid.trim() != activeSessionGuid) {
      throw StateError(
        "Wearable replay session ${recordSessionGuid.trim()} does not match "
        "active session $activeSessionGuid.",
      );
    }
    final documentsDirectory = await _documentsDirectoryProvider();
    final sessionDirectory =
        Directory("${documentsDirectory.path}/session_$activeSessionGuid");
    await sessionDirectory.create(recursive: true);
    return sessionDirectory;
  }

  Future<File> _writeJsonFile(
    File file,
    Map<String, dynamic> payload, {
    required String logLabel,
  }) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(payload), flush: true);
    LogService.instance.registerLog("$logLabel saved to ${file.path}");
    return file;
  }

  Future<List<String>> _filePathsIn(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return const [];
    }
    final files = directory
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .toList()
      ..sort();
    return files;
  }

  Future<List<String>> _povMediaPathsFrom(
      List<String> povRecordingFiles) async {
    final mediaPaths = <String>[];
    for (final recordingPath in povRecordingFiles) {
      final decoded = jsonDecode(await File(recordingPath).readAsString());
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final mediaPath = decoded["mediaPath"];
      if (mediaPath is String && mediaPath.trim().isNotEmpty) {
        mediaPaths.add(mediaPath.trim());
      }
    }
    mediaPaths.sort();
    return mediaPaths;
  }

  Future<File?> _stagePovMediaFile(
    Directory sessionDirectory,
    String mediaPath,
    String recordingId,
  ) async {
    final sourceFile = File(mediaPath);
    if (!sourceFile.existsSync()) {
      return null;
    }
    final stagedFile = File(
      "${sessionDirectory.path}/wearables/pov-media/"
      "$recordingId${_fileExtension(sourceFile.path)}",
    );
    await stagedFile.parent.create(recursive: true);
    await sourceFile.copy(stagedFile.path);
    return stagedFile;
  }
}

String _fileExtension(String path) {
  final filename = path.split(Platform.pathSeparator).last;
  final dotIndex = filename.lastIndexOf(".");
  if (dotIndex <= 0 || dotIndex == filename.length - 1) {
    return "";
  }
  return filename.substring(dotIndex);
}
