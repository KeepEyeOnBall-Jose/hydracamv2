import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:path_provider/path_provider.dart";

import "../models/capture_context_metadata.dart";

/// Metadata of one exact returned path, independent of the next recording.
/// Context is serialized on capture and decoded afresh for each reader.
class RecordedVideoSnapshot {
  RecordedVideoSnapshot._({
    required this.captureId,
    required this.path,
    required this.sourcePath,
    required this.startedAt,
    required this.stoppedAt,
    required this.sessionGuid,
    required String? contextJson,
  }) : _contextJson = contextJson;

  factory RecordedVideoSnapshot.capture({
    required String captureId,
    required String path,
    required DateTime? startedAt,
    required DateTime? stoppedAt,
    required MediaCaptureContext? context,
    String? sessionGuid,
  }) =>
      RecordedVideoSnapshot._(
        captureId: captureId,
        path: path,
        sourcePath: path,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        sessionGuid: sessionGuid,
        contextJson: context == null ? null : jsonEncode(context.toJson()),
      );

  final String captureId;
  final String path;
  final String sourcePath;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String? sessionGuid;
  final String? _contextJson;

  MediaCaptureContext? get context => _contextJson == null
      ? null
      : MediaCaptureContext.fromJson(
          Map<String, dynamic>.from(jsonDecode(_contextJson)));

  RecordedVideoSnapshot atPath(String returnedPath) => RecordedVideoSnapshot._(
        captureId: captureId,
        path: returnedPath,
        sourcePath: sourcePath,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        sessionGuid: sessionGuid,
        contextJson: _contextJson,
      );

  Map<String, dynamic> toJson() => {
        "status": "pending-recovery",
        "mediaPersisted": false,
        "captureId": captureId,
        "path": path,
        "sourcePath": sourcePath,
        "startedAt": startedAt?.toIso8601String(),
        "stoppedAt": stoppedAt?.toIso8601String(),
        "sessionGuid": sessionGuid,
        "context": _contextJson == null ? null : jsonDecode(_contextJson),
      };

  factory RecordedVideoSnapshot.fromJson(Map<String, dynamic> json) =>
      RecordedVideoSnapshot._(
        captureId: json["captureId"] as String,
        path: json["path"] as String,
        sourcePath: json["sourcePath"] as String,
        startedAt: DateTime.tryParse(json["startedAt"]?.toString() ?? ""),
        stoppedAt: DateTime.tryParse(json["stoppedAt"]?.toString() ?? ""),
        sessionGuid: json["sessionGuid"] as String?,
        contextJson:
            json["context"] == null ? null : jsonEncode(json["context"]),
      );
}

/// Bounded recent lookup plus durable, explicitly pending recovery receipts.
/// Acknowledgement follows the existing consumer's durable capture save. It
/// deletes only our metadata receipt; original media is never removed here.
class RecordedVideoSnapshots {
  RecordedVideoSnapshots({
    Future<Directory> Function()? directory,
    this.capacity = 64,
  })  : assert(capacity > 0),
        _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;
  final int capacity;
  Future<Directory>? _opened;
  final LinkedHashMap<String, RecordedVideoSnapshot> _recent = LinkedHashMap();

  int get cachedCount => _recent.length;

  static Future<Directory> _defaultDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory("${documents.path}/recording-recovery");
  }

  Future<Directory> _root() => _opened ??= _directory();

  Future<File> _receipt(String id) async {
    if (!RegExp(r"^[a-zA-Z0-9_-]{1,80}$").hasMatch(id)) {
      throw const FormatException("Invalid recording capture identity");
    }
    final root = await _root();
    await root.create(recursive: true);
    return File("${root.path}/$id.json");
  }

  void _cache(RecordedVideoSnapshot snapshot) {
    _recent.remove(snapshot.path);
    _recent[snapshot.path] = snapshot;
    while (_recent.length > capacity) {
      _recent.remove(_recent.keys.first);
    }
  }

  Future<void> remember(RecordedVideoSnapshot snapshot) async {
    final receipt = await _receipt(snapshot.captureId);
    final temporary = File("${receipt.path}.tmp");
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await temporary.rename(receipt.path);
    _cache(snapshot);
  }

  Future<RecordedVideoSnapshot?> forPath(String path) async {
    final cached = _recent[path];
    if (cached != null) {
      _cache(cached);
      return cached;
    }
    final root = await _root();
    if (!await root.exists()) {
      return null;
    }
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith(".json")) {
        continue;
      }
      final snapshot = RecordedVideoSnapshot.fromJson(
          Map<String, dynamic>.from(jsonDecode(await entity.readAsString())));
      if (snapshot.path == path) {
        _cache(snapshot);
        return snapshot;
      }
    }
    return null;
  }

  Future<void> acknowledge(RecordedVideoSnapshot snapshot) async {
    final receipt = await _receipt(snapshot.captureId);
    try {
      if (await receipt.exists()) {
        await receipt.delete();
      }
    } on FileSystemException {
      if (await receipt.exists()) {
        rethrow;
      }
    }
    // Keep recent immutable values available to concurrent/repeated readers.
    // An older acknowledgement never replaces a later capture at this path.
    if (_recent[snapshot.path]?.captureId == snapshot.captureId) {
      _cache(snapshot);
    }
  }
}
