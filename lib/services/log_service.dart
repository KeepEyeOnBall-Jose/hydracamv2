import "dart:collection";

import "package:flutter/foundation.dart";

/// A singleton service to manage application logs.
class LogService {
  static final LogService _instance = LogService._internal();
  final List<Map<String, dynamic>> _logs = [];

  LogService._internal();

  /// Provides the single instance of the log service.
  static LogService get instance => _instance;

  /// Registers a log entry.
  ///
  /// [message]: The log message.
  /// [timestamp]: Timestamp of the log, defaults to the current time.
  /// [function]: The optional function name that generated the log.
  /// [file]: The optional file name that generated the log.
  void registerLog(String message,
      {DateTime? timestamp, String? function, String? file}) {
    final logEntry = {
      "message": message,
      "timestamp": timestamp ?? DateTime.now(),
      "function": function,
      "file": file,
    };
    _logs.add(logEntry);
    if (kDebugMode) {
      print("Log registered: $logEntry");
    }
  }

  /// Retrieves all logs in a read-only format.
  UnmodifiableListView<Map<String, dynamic>> get logs =>
      UnmodifiableListView(_logs);

  /// Clears all logs.
  void clearLogs() {
    _logs.clear();
  }
}
