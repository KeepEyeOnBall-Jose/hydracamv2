import "dart:io";
import "dart:math" as math;

// `crypto` is declared under dev_dependencies in pubspec.yaml (outside this
// slice's owned files), so suppress depend_on_referenced_packages until it is
// promoted to dependencies.
// ignore: depend_on_referenced_packages
import "package:crypto/crypto.dart";

import "fixed_camera_hls_recorder_service.dart";
import "phonecore_live_upload_service.dart";

/// Sleep callback used between bounded `drainOnce` iterations.
typedef PhoneCoreLiveUploadSleep = Future<void> Function(Duration duration);

/// Configuration for uploading a finalized fixed-camera recording to K3 via
/// native PhoneCore (`PhoneCoreLiveUploadService`).
class PhoneCoreLiveUploadConfig {
  const PhoneCoreLiveUploadConfig({
    required this.uploadGrant,
    required this.ingestUrl,
    this.slot = "A",
    this.tier = "proxy",
    this.maxDrainStepsPerCall = 16,
    this.maxDrainIterations = 32,
    this.drainDelay = const Duration(milliseconds: 250),
  });

  final String uploadGrant;
  final String ingestUrl;
  final String slot;
  final String tier;
  final int maxDrainStepsPerCall;
  final int maxDrainIterations;
  final Duration drainDelay;
}

/// Summary returned after enqueueing segments and running the bounded drain
/// loop on [PhoneCoreLiveUploadService].
class PhoneCoreLiveUploadBridgeResult {
  const PhoneCoreLiveUploadBridgeResult({
    required this.sessionId,
    required this.slot,
    required this.tier,
    required this.enqueuedSegments,
    required this.drainIterations,
    required this.totalDrainSteps,
    required this.hasPendingWork,
    required this.snapshot,
  });

  final String sessionId;
  final String slot;
  final String tier;
  final int enqueuedSegments;
  final int drainIterations;
  final int totalDrainSteps;
  final bool hasPendingWork;
  final PhoneCoreLiveUploadSnapshot snapshot;

  bool get isComplete => snapshot.isComplete;
  int get totalSegments => snapshot.totalSegments;
  int get verifiedSegments => snapshot.verifiedSegments;
  int get activeSegments => snapshot.activeSegments;
  int get heldSegments => snapshot.heldSegments;
  int get failedSegments => snapshot.failedSegments;
  int get conflictSegments => snapshot.conflictSegments;
  int get pendingBytes => snapshot.pendingBytes;
  String? get manifestState => snapshot.manifestState;
}

/// Bridges a finalized [FixedCameraHlsRecordingResult] into PhoneCore's
/// native K3 live upload pipeline (`startSession` -> `enqueueSegment` x N ->
/// `markRecordingStopped` -> bounded `drainOnce` -> `getSnapshot`).
class PhoneCoreLiveUploadBridge {
  PhoneCoreLiveUploadBridge({
    PhoneCoreLiveUploadService? uploadService,
    PhoneCoreLiveUploadSleep? sleep,
    int Function()? nowMs,
  })  : _uploadService = uploadService ?? PhoneCoreLiveUploadService(),
        _sleep = sleep ?? Future<void>.delayed,
        _customNowMs = nowMs;

  static const Set<String> _supportedTiers = {"proxy", "master"};
  static const int _fallbackSegmentDurationMs = 2000;

  final PhoneCoreLiveUploadService _uploadService;
  final PhoneCoreLiveUploadSleep _sleep;
  final int Function()? _customNowMs;

  /// Validates [recording] segments, computes real SHA-256 digests, registers
  /// the PhoneCore session, enqueues all segments with 1-based `seq` and
  /// monotonic timestamps, marks the recording stopped, and drains within the
  /// configured iteration budget.
  Future<PhoneCoreLiveUploadBridgeResult> uploadFinalizedRecording({
    required String sessionId,
    required FixedCameraHlsRecordingResult recording,
    required PhoneCoreLiveUploadConfig config,
  }) async {
    final trimmedSessionId = _requireNonBlank(sessionId, "sessionId");
    final trimmedSlot = _requireNonBlank(config.slot, "config.slot");
    final trimmedGrant = _requireNonBlank(
      config.uploadGrant,
      "config.uploadGrant",
    );
    final trimmedIngestUrl = _requireNonBlank(
      config.ingestUrl,
      "config.ingestUrl",
    );
    if (!_supportedTiers.contains(config.tier)) {
      throw ArgumentError.value(
        config.tier,
        "config.tier",
        "Tier must be one of ${_supportedTiers.join(", ")}.",
      );
    }
    if (config.maxDrainStepsPerCall <
            PhoneCoreLiveUploadService.minDrainSteps ||
        config.maxDrainStepsPerCall >
            PhoneCoreLiveUploadService.maxDrainSteps) {
      throw RangeError.range(
        config.maxDrainStepsPerCall,
        PhoneCoreLiveUploadService.minDrainSteps,
        PhoneCoreLiveUploadService.maxDrainSteps,
        "config.maxDrainStepsPerCall",
      );
    }
    if (config.maxDrainIterations < 1) {
      throw RangeError.value(
        config.maxDrainIterations,
        "config.maxDrainIterations",
        "Must be at least 1.",
      );
    }
    if (config.drainDelay.isNegative) {
      throw ArgumentError.value(
        config.drainDelay,
        "config.drainDelay",
        "Must not be negative.",
      );
    }
    if (recording.state != FixedCameraHlsRecordingState.finalized) {
      throw StateError(
        "Fixed-camera HLS recording must be finalized before K3 upload.",
      );
    }
    if (recording.chunkPaths.isEmpty) {
      throw ArgumentError.value(
        recording.chunkPaths,
        "recording.chunkPaths",
        "Recording must contain at least one finalized segment.",
      );
    }

    final segments = await _prepareSegments(recording);
    final nowMs =
        _customNowMs?.call() ?? DateTime.now().toUtc().millisecondsSinceEpoch;

    await _uploadService.startSession(
      sessionId: trimmedSessionId,
      slot: trimmedSlot,
      uploadGrant: trimmedGrant,
      ingestUrl: trimmedIngestUrl,
      nowMs: _customNowMs != null ? nowMs : null,
    );

    for (final segment in segments) {
      await _uploadService.enqueueSegment(
        sessionId: trimmedSessionId,
        slot: trimmedSlot,
        tier: config.tier,
        seq: segment.seq,
        filePath: segment.filePath,
        sha256: segment.sha256,
        mediaStartServerMs: segment.mediaStartServerMs,
        durationMs: segment.durationMs,
      );
    }

    final stoppedAtMs = _resolveStoppedAtMs(
      recording: recording,
      segments: segments,
      fallbackNowMs: nowMs,
    );
    await _uploadService.markRecordingStopped(
      sessionId: trimmedSessionId,
      stoppedAtMs: stoppedAtMs,
    );

    PhoneCoreLiveUploadSnapshot? finalSnapshot;
    var drainIterations = 0;
    var totalDrainSteps = 0;
    var hasPendingWork = true;

    for (var i = 0; i < config.maxDrainIterations; i++) {
      final drain = await _uploadService.drainOnce(
        maxSteps: config.maxDrainStepsPerCall,
      );
      drainIterations += 1;
      totalDrainSteps += drain.stepsTaken;
      hasPendingWork = drain.hasPendingWork;

      if (!drain.hasPendingWork) {
        finalSnapshot = null;
        break;
      }

      finalSnapshot = await _uploadService.getSnapshot(trimmedSessionId);
      if (finalSnapshot?.isComplete ?? false) {
        break;
      }

      if (i + 1 < config.maxDrainIterations &&
          !drain.didWork &&
          config.drainDelay > Duration.zero) {
        await _sleep(config.drainDelay);
      }
    }

    finalSnapshot ??= await _uploadService.getSnapshot(trimmedSessionId);
    if (finalSnapshot == null) {
      throw StateError(
        "Missing PhoneCore live upload snapshot for session '$trimmedSessionId'.",
      );
    }

    return PhoneCoreLiveUploadBridgeResult(
      sessionId: trimmedSessionId,
      slot: trimmedSlot,
      tier: config.tier,
      enqueuedSegments: segments.length,
      drainIterations: drainIterations,
      totalDrainSteps: totalDrainSteps,
      hasPendingWork: hasPendingWork,
      snapshot: finalSnapshot,
    );
  }

  Future<List<_PreparedSegment>> _prepareSegments(
    FixedCameraHlsRecordingResult recording,
  ) async {
    final count = recording.chunkPaths.length;
    final totalDurationMs = _resolveTotalDurationMs(recording, count);
    final baseStartMs = _resolveBaseStartMs(recording, totalDurationMs);

    final baseSegmentMs = totalDurationMs ~/ count;
    final remainderMs = totalDurationMs % count;

    final segments = <_PreparedSegment>[];
    var cursorMs = baseStartMs;

    for (var i = 0; i < count; i++) {
      final rawPath = recording.chunkPaths[i];
      final trimmedPath = rawPath.trim();
      if (trimmedPath.isEmpty) {
        throw ArgumentError.value(
          rawPath,
          "recording.chunkPaths[$i]",
          "Segment path must not be blank.",
        );
      }
      final file = File(trimmedPath);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw FileSystemException(
          "Fixed-camera HLS segment file does not exist.",
          trimmedPath,
        );
      }

      final digest = await sha256.bind(file.openRead()).first;
      final durationMs = baseSegmentMs + (i < remainderMs ? 1 : 0);
      segments.add(
        _PreparedSegment(
          seq: i + 1,
          filePath: trimmedPath,
          sha256: digest.toString(),
          mediaStartServerMs: cursorMs,
          durationMs: durationMs,
        ),
      );
      cursorMs += durationMs;
    }

    return segments;
  }

  int _resolveTotalDurationMs(
    FixedCameraHlsRecordingResult recording,
    int segmentCount,
  ) {
    final durationSeconds = recording.durationSeconds;
    if (durationSeconds != null &&
        durationSeconds.isFinite &&
        durationSeconds > 0) {
      return math.max(segmentCount, (durationSeconds * 1000).round());
    }

    final startedAt = recording.startedAt;
    final finalizedAt = recording.finalizedAt;
    if (startedAt != null && finalizedAt != null) {
      final diffMs = finalizedAt.difference(startedAt).inMilliseconds;
      if (diffMs > 0) {
        return math.max(segmentCount, diffMs);
      }
    }

    final targetSeconds = recording.targetDurationSeconds;
    if (targetSeconds != null && targetSeconds > 0) {
      return math.max(segmentCount, targetSeconds * 1000 * segmentCount);
    }

    return segmentCount * _fallbackSegmentDurationMs;
  }

  int _resolveBaseStartMs(
    FixedCameraHlsRecordingResult recording,
    int totalDurationMs,
  ) {
    final startedAt = recording.startedAt;
    if (startedAt != null) {
      return startedAt.toUtc().millisecondsSinceEpoch;
    }
    final finalizedAt = recording.finalizedAt;
    if (finalizedAt != null) {
      return finalizedAt.toUtc().millisecondsSinceEpoch - totalDurationMs;
    }
    return _customNowMs?.call() ??
        DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  int _resolveStoppedAtMs({
    required FixedCameraHlsRecordingResult recording,
    required List<_PreparedSegment> segments,
    required int fallbackNowMs,
  }) {
    final finalizedMs = recording.finalizedAt?.toUtc().millisecondsSinceEpoch;
    if (finalizedMs != null && finalizedMs > 0) {
      return finalizedMs;
    }
    final last = segments.last;
    final computedEndMs = last.mediaStartServerMs + last.durationMs;
    if (computedEndMs > 0) {
      return computedEndMs;
    }
    return fallbackNowMs > 0 ? fallbackNowMs : 1;
  }

  String _requireNonBlank(String value, String name) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, "$name must not be blank.");
    }
    return trimmed;
  }
}

class _PreparedSegment {
  const _PreparedSegment({
    required this.seq,
    required this.filePath,
    required this.sha256,
    required this.mediaStartServerMs,
    required this.durationMs,
  });

  final int seq;
  final String filePath;
  final String sha256;
  final int mediaStartServerMs;
  final int durationMs;
}
