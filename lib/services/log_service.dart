import "dart:collection";
import "dart:async";
import "dart:convert";
import "dart:developer" as developer;
import "dart:io";

import "package:flutter/foundation.dart";
import "package:path_provider/path_provider.dart";

/// A singleton service to manage application logs.
class LogService {
  static final LogService _instance = LogService._internal();
  final List<Map<String, dynamic>> _logs = [];
  Future<File?>? _traceFileFuture;
  Future<void> _persistedWriteQueue = Future<void>.value();
  bool _tracePersistenceDisabled = false;
  String? _traceFilePath;

  LogService._internal();

  /// Provides the single instance of the log service.
  static LogService get instance => _instance;

  String? get traceFilePath => _traceFilePath;

  /// Registers a log entry.
  ///
  /// [message]: The log message.
  /// [timestamp]: Timestamp of the log, defaults to the current time.
  /// [function]: The optional function name that generated the log.
  /// [file]: The optional file name that generated the log.
  void registerLog(String message,
      {DateTime? timestamp, String? function, String? file}) {
    final entryTimestamp = timestamp ?? DateTime.now();
    final logEntry = {
      "message": message,
      "timestamp": entryTimestamp,
      "function": function,
      "file": file,
    };
    _logs.add(logEntry);
    _persistLogEntry(logEntry);
    if (!kReleaseMode) {
      developer.log(
        message,
        name: file ?? "HydraCam",
        time: entryTimestamp,
      );
    }
    if (kDebugMode) {
      debugPrint("Log registered: $logEntry");
    }
  }

  void registerError(String message, Object error, StackTrace stackTrace,
      {String? function, String? file}) {
    registerLog(
      "$message: $error\n$stackTrace",
      function: function,
      file: file,
    );
  }

  /// Retrieves all logs in a read-only format.
  UnmodifiableListView<Map<String, dynamic>> get logs =>
      UnmodifiableListView(_logs);

  /// Clears all logs.
  void clearLogs() {
    _logs.clear();
  }

  Future<List<String>> readPersistedLogLines({int limit = 500}) async {
    final traceFile = await _getTraceFile();
    if (traceFile == null || !await traceFile.exists()) {
      return [];
    }

    final lines = await traceFile.readAsLines();
    if (lines.length <= limit) {
      return lines;
    }
    return lines.sublist(lines.length - limit);
  }

  void _persistLogEntry(Map<String, dynamic> logEntry) {
    _persistedWriteQueue =
        _persistedWriteQueue.then((_) => _writePersistedLogEntry(logEntry));
    unawaited(_persistedWriteQueue);
  }

  Future<void> _writePersistedLogEntry(Map<String, dynamic> logEntry) async {
    try {
      final traceFile = await _getTraceFile();
      if (traceFile == null) {
        return;
      }

      final payload = {
        "message": logEntry["message"],
        "timestamp": (logEntry["timestamp"] as DateTime).toIso8601String(),
        "function": logEntry["function"],
        "file": logEntry["file"],
      };

      await traceFile.parent.create(recursive: true);
      await traceFile.writeAsString(
        "${jsonEncode(payload)}\n",
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      _tracePersistenceDisabled = true;
      if (kDebugMode) {
        debugPrint("Trace persistence disabled: $error");
      }
    }
  }

  Future<File?> _getTraceFile() {
    if (_tracePersistenceDisabled) {
      return Future<File?>.value(null);
    }
    return _traceFileFuture ??= _createTraceFile();
  }

  Future<File?> _createTraceFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDirectory = Directory("${directory.path}/logs");
      await logDirectory.create(recursive: true);
      final traceStartedAt = DateTime.now()
          .toIso8601String()
          .replaceAll(":", "-")
          .replaceAll(".", "-");
      final traceFile =
          File("${logDirectory.path}/hydracam-trace-$traceStartedAt.ndjson");
      _traceFilePath = traceFile.path;
      return traceFile;
    } catch (error) {
      _tracePersistenceDisabled = true;
      if (kDebugMode) {
        debugPrint("Trace file unavailable: $error");
      }
      return null;
    }
  }
}
