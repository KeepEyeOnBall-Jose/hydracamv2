import "package:flutter/foundation.dart";

class DebugSessionPolicy {
  DebugSessionPolicy({
    bool? debugBuild,
    DateTime Function()? now,
    String? platformLabel,
  })  : _debugBuild = debugBuild ?? kDebugMode,
        _now = now ?? DateTime.now,
        _platformLabel = platformLabel ?? defaultTargetPlatform.name;

  final bool _debugBuild;
  final DateTime Function() _now;
  final String _platformLabel;

  bool get debugBuild => _debugBuild;

  String defaultSessionId() {
    final now = _now().toUtc();
    if (!_debugBuild) {
      return now.toIso8601String();
    }
    final compactTimestamp = now
        .toIso8601String()
        .replaceAll("-", "")
        .replaceAll(":", "")
        .replaceAll(".000", "");
    return "debug-$_platformLabel-$compactTimestamp";
  }

  bool shouldDeleteUploadedLocalMedia({required bool debugSession}) {
    return _debugBuild && debugSession;
  }
}
