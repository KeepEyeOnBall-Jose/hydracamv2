import "package:flutter/services.dart";

import "../models/json_value_parsers.dart";

/// Immutable segment row returned inside [PhoneCoreLiveUploadSnapshot].
class PhoneCoreLiveUploadItem {
  const PhoneCoreLiveUploadItem({
    required this.key,
    required this.sessionId,
    required this.slot,
    required this.tier,
    required this.seq,
    required this.filePath,
    required this.bytes,
    required this.sha256,
    required this.mediaStartServerMs,
    required this.durationMs,
    required this.state,
    required this.uploadId,
    required this.verifyRestarts,
    required this.attempts,
    required this.nextAttemptAtMs,
    required this.lastError,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory PhoneCoreLiveUploadItem.fromMap(Object? raw) {
    final map = _requireMap(raw, "PhoneCoreLiveUploadItem");
    return PhoneCoreLiveUploadItem(
      key: _requireNonEmptyString(map, "key"),
      sessionId: _requireNonEmptyString(map, "sessionId"),
      slot: _requireNonEmptyString(map, "slot"),
      tier: _requireNonEmptyString(map, "tier"),
      seq: _requireInt(map, "seq"),
      filePath: _requireNonEmptyString(map, "filePath"),
      bytes: _requireInt(map, "bytes"),
      sha256: _requireNonEmptyString(map, "sha256"),
      mediaStartServerMs: _requireInt(map, "mediaStartServerMs"),
      durationMs: _requireInt(map, "durationMs"),
      state: _requireNonEmptyString(map, "state"),
      uploadId: _optionalString(map, "uploadId"),
      verifyRestarts: _requireInt(map, "verifyRestarts"),
      attempts: _requireInt(map, "attempts"),
      nextAttemptAtMs: _requireInt(map, "nextAttemptAtMs"),
      lastError: _optionalString(map, "lastError"),
      createdAtMs: _requireInt(map, "createdAtMs"),
      updatedAtMs: _requireInt(map, "updatedAtMs"),
    );
  }

  final String key;
  final String sessionId;
  final String slot;
  final String tier;
  final int seq;
  final String filePath;
  final int bytes;
  final String sha256;
  final int mediaStartServerMs;
  final int durationMs;
  final String state;
  final String? uploadId;
  final int verifyRestarts;
  final int attempts;
  final int nextAttemptAtMs;
  final String? lastError;
  final int createdAtMs;
  final int updatedAtMs;
}

/// Immutable point-in-time upload snapshot for one live recording session.
class PhoneCoreLiveUploadSnapshot {
  PhoneCoreLiveUploadSnapshot({
    required this.sessionId,
    required this.slot,
    required List<String> grantedTiers,
    required this.stoppedAtMs,
    required this.lastSeqProxy,
    required this.lastSeqMaster,
    required this.manifestState,
    required this.totalSegments,
    required this.activeSegments,
    required this.verifiedSegments,
    required this.heldSegments,
    required this.failedSegments,
    required this.conflictSegments,
    required this.pendingBytes,
    required this.isComplete,
    required List<PhoneCoreLiveUploadItem> items,
  })  : grantedTiers = List<String>.unmodifiable(grantedTiers),
        items = List<PhoneCoreLiveUploadItem>.unmodifiable(items);

  factory PhoneCoreLiveUploadSnapshot.fromMap(Object? raw) {
    final map = _requireMap(raw, "PhoneCoreLiveUploadSnapshot");
    return PhoneCoreLiveUploadSnapshot(
      sessionId: _requireNonEmptyString(map, "sessionId"),
      slot: _requireNonEmptyString(map, "slot"),
      grantedTiers: _requireStringList(map, "grantedTiers"),
      stoppedAtMs: _requireInt(map, "stoppedAtMs"),
      lastSeqProxy: _requireInt(map, "lastSeqProxy"),
      lastSeqMaster: _requireInt(map, "lastSeqMaster"),
      manifestState: _optionalString(map, "manifestState"),
      totalSegments: _requireInt(map, "totalSegments"),
      activeSegments: _requireInt(map, "activeSegments"),
      verifiedSegments: _requireInt(map, "verifiedSegments"),
      heldSegments: _requireInt(map, "heldSegments"),
      failedSegments: _requireInt(map, "failedSegments"),
      conflictSegments: _requireInt(map, "conflictSegments"),
      pendingBytes: _requireInt(map, "pendingBytes"),
      isComplete: _requireBool(map, "isComplete"),
      items: _requireItemList(map, "items"),
    );
  }

  final String sessionId;
  final String slot;
  final List<String> grantedTiers;
  final int stoppedAtMs;
  final int lastSeqProxy;
  final int lastSeqMaster;
  final String? manifestState;
  final int totalSegments;
  final int activeSegments;
  final int verifiedSegments;
  final int heldSegments;
  final int failedSegments;
  final int conflictSegments;
  final int pendingBytes;
  final bool isComplete;
  final List<PhoneCoreLiveUploadItem> items;
}

/// Summary of one bounded native `drainOnce` invocation.
class PhoneCoreDrainResult {
  const PhoneCoreDrainResult({
    required this.stepsTaken,
    required this.didWork,
    required this.hasPendingWork,
    required this.nextWakeAtMs,
  });

  factory PhoneCoreDrainResult.fromMap(Object? raw) {
    final map = _requireMap(raw, "PhoneCoreDrainResult");
    return PhoneCoreDrainResult(
      stepsTaken: _requireInt(map, "stepsTaken"),
      didWork: _requireBool(map, "didWork"),
      hasPendingWork: _requireBool(map, "hasPendingWork"),
      nextWakeAtMs: _optionalInt(map, "nextWakeAtMs"),
    );
  }

  final int stepsTaken;
  final bool didWork;
  final bool hasPendingWork;
  final int? nextWakeAtMs;
}

/// Next-wake status across queued live-session uploads and manifests.
class PhoneCorePendingWork {
  const PhoneCorePendingWork({
    required this.hasPendingWork,
    required this.nextWakeAtMs,
  });

  factory PhoneCorePendingWork.fromMap(Object? raw) {
    final map = _requireMap(raw, "PhoneCorePendingWork");
    return PhoneCorePendingWork(
      hasPendingWork: _requireBool(map, "hasPendingWork"),
      nextWakeAtMs: _optionalInt(map, "nextWakeAtMs"),
    );
  }

  final bool hasPendingWork;
  final int? nextWakeAtMs;
}

/// Thin Flutter `MethodChannel` bridge over native `PhoneCoreLiveSessionUploader`.
class PhoneCoreLiveUploadService {
  PhoneCoreLiveUploadService({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const String channelName = "hydracamv2/phonecore_live_upload";
  static const int minDrainSteps = 1;
  static const int maxDrainSteps = 50;
  static const MethodChannel _defaultChannel = MethodChannel(channelName);

  final MethodChannel _channel;

  Future<PhoneCoreLiveUploadSnapshot> startSession({
    required String sessionId,
    required String slot,
    required String uploadGrant,
    required String ingestUrl,
    int? nowMs,
  }) async {
    final raw = await _channel.invokeMethod<Object?>("startSession", {
      "sessionId": sessionId,
      "slot": slot,
      "uploadGrant": uploadGrant,
      "ingestUrl": ingestUrl,
      if (nowMs != null) "nowMs": nowMs,
    });
    return PhoneCoreLiveUploadSnapshot.fromMap(raw);
  }

  Future<PhoneCoreLiveUploadSnapshot> enqueueSegment({
    required String sessionId,
    required String slot,
    required String tier,
    required int seq,
    required String filePath,
    required String sha256,
    required int mediaStartServerMs,
    required int durationMs,
    int? nowMs,
  }) async {
    final raw = await _channel.invokeMethod<Object?>("enqueueSegment", {
      "sessionId": sessionId,
      "slot": slot,
      "tier": tier,
      "seq": seq,
      "filePath": filePath,
      "sha256": sha256,
      "mediaStartServerMs": mediaStartServerMs,
      "durationMs": durationMs,
      if (nowMs != null) "nowMs": nowMs,
    });
    return PhoneCoreLiveUploadSnapshot.fromMap(raw);
  }

  Future<PhoneCoreLiveUploadSnapshot?> markRecordingStopped({
    required String sessionId,
    int? stoppedAtMs,
  }) async {
    final raw = await _channel.invokeMethod<Object?>("markRecordingStopped", {
      "sessionId": sessionId,
      if (stoppedAtMs != null) "stoppedAtMs": stoppedAtMs,
    });
    if (raw == null) {
      return null;
    }
    return PhoneCoreLiveUploadSnapshot.fromMap(raw);
  }

  Future<PhoneCoreDrainResult> drainOnce({int? maxSteps}) async {
    if (maxSteps != null &&
        (maxSteps < minDrainSteps || maxSteps > maxDrainSteps)) {
      throw RangeError.range(
        maxSteps,
        minDrainSteps,
        maxDrainSteps,
        "maxSteps",
      );
    }
    final raw = await _channel.invokeMethod<Object?>(
      "drainOnce",
      maxSteps == null ? null : {"maxSteps": maxSteps},
    );
    return PhoneCoreDrainResult.fromMap(raw);
  }

  Future<PhoneCoreLiveUploadSnapshot?> getSnapshot(String sessionId) async {
    final raw = await _channel.invokeMethod<Object?>(
      "getSnapshot",
      {"sessionId": sessionId},
    );
    if (raw == null) {
      return null;
    }
    return PhoneCoreLiveUploadSnapshot.fromMap(raw);
  }

  Future<PhoneCorePendingWork> hasPendingWork() async {
    final raw = await _channel.invokeMethod<Object?>("hasPendingWork");
    return PhoneCorePendingWork.fromMap(raw);
  }
}

Map<String, dynamic> _requireMap(Object? raw, String label) {
  final map = toStringKeyedMap(raw);
  if (map == null) {
    throw FormatException("Expected map for $label.");
  }
  return map;
}

String _requireNonEmptyString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException("Missing or invalid string field: $key.");
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException("Invalid string field: $key.");
  }
  return value;
}

int _requireInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException("Missing or invalid int field: $key.");
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException("Invalid int field: $key.");
  }
  return value;
}

bool _requireBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException("Missing or invalid bool field: $key.");
  }
  return value;
}

List<String> _requireStringList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) {
    throw FormatException("Missing or invalid list field: $key.");
  }
  final result = <String>[];
  for (final element in value) {
    if (element is! String) {
      throw FormatException("Invalid string element in list field: $key.");
    }
    result.add(element);
  }
  return result;
}

List<PhoneCoreLiveUploadItem> _requireItemList(
  Map<String, dynamic> map,
  String key,
) {
  final value = map[key];
  if (value is! List) {
    throw FormatException("Missing or invalid list field: $key.");
  }
  return value.map(PhoneCoreLiveUploadItem.fromMap).toList(growable: false);
}
