import "dart:async";
import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

import "log_service.dart";
import "phonecore_live_upload_bridge.dart";
import "phonecore_live_upload_service.dart";

/// Outcome of one startup/resume recovery pass over persisted PhoneCore K3 queue.
enum PhoneCoreLiveUploadRecoveryStatus {
  /// Native upload channel is unavailable or threw [MissingPluginException].
  unavailable,

  /// Persisted queue had no pending work to drain.
  idle,

  /// Drained persisted work until `hasPendingWork` became false.
  drained,

  /// Stopped cleanly at recovery budget or distant `nextWakeAtMs` backoff.
  deferred,

  /// Unexpected [PlatformException] or payload error prevented draining.
  failed,
}

/// Bounds for one startup/resume recovery cycle.
class PhoneCoreLiveUploadRecoveryConfig {
  const PhoneCoreLiveUploadRecoveryConfig({
    this.maxStepsPerDrain = 16,
    this.maxDrainIterations = 8,
    this.maxTotalRecoveryDuration = const Duration(seconds: 20),
    this.maxWakeWaitPerStep = const Duration(seconds: 5),
    this.fallbackIdleDelay = const Duration(milliseconds: 250),
  });

  final int maxStepsPerDrain;
  final int maxDrainIterations;
  final Duration maxTotalRecoveryDuration;
  final Duration maxWakeWaitPerStep;
  final Duration fallbackIdleDelay;
}

/// Summary returned after one single-flight recovery cycle completes.
class PhoneCoreLiveUploadRecoveryResult {
  const PhoneCoreLiveUploadRecoveryResult({
    required this.status,
    this.drainIterations = 0,
    this.totalStepsTaken = 0,
    this.hasPendingWork = false,
    this.nextWakeAtMs,
    this.pendingSessionCount = 0,
    this.pendingSegmentCount = 0,
    this.pendingBytes = 0,
    this.pendingSessionIds = const <String>[],
    this.errorMessage,
  });

  final PhoneCoreLiveUploadRecoveryStatus status;
  final int drainIterations;
  final int totalStepsTaken;
  final bool hasPendingWork;
  final int? nextWakeAtMs;
  final int pendingSessionCount;
  final int pendingSegmentCount;
  final int pendingBytes;
  final List<String> pendingSessionIds;
  final String? errorMessage;

  bool get didWork => totalStepsTaken > 0;
}

/// Single-flight bounded coordinator that checks `hasPendingWork()` on startup
/// or app resume and drains persisted PhoneCore K3 sessions without blocking UI.
class PhoneCoreLiveUploadRecovery {
  PhoneCoreLiveUploadRecovery({
    PhoneCoreLiveUploadService? uploadService,
    PhoneCoreLiveUploadSleep? sleep,
    int Function()? nowMs,
    PhoneCoreLiveUploadRecoveryConfig config =
        const PhoneCoreLiveUploadRecoveryConfig(),
    bool Function()? isPlatformSupported,
    void Function(String message)? log,
  })  : _uploadService = uploadService ?? PhoneCoreLiveUploadService(),
        _sleep = sleep ?? Future<void>.delayed,
        _nowMs = nowMs ?? _defaultNowMs,
        _config = config,
        _isPlatformSupported =
            isPlatformSupported ?? _defaultIsPlatformSupported,
        _log = log ?? LogService.instance.registerLog {
    _validateConfig(config);
  }

  static final PhoneCoreLiveUploadRecovery instance =
      PhoneCoreLiveUploadRecovery();

  final PhoneCoreLiveUploadService _uploadService;
  final PhoneCoreLiveUploadSleep _sleep;
  final int Function() _nowMs;
  final PhoneCoreLiveUploadRecoveryConfig _config;
  final bool Function() _isPlatformSupported;
  final void Function(String message) _log;

  Future<PhoneCoreLiveUploadRecoveryResult>? _inFlightRecovery;
  PhoneCoreLiveUploadRecoveryResult? _lastResult;

  bool get isRecovering => _inFlightRecovery != null;
  PhoneCoreLiveUploadRecoveryResult? get lastResult => _lastResult;

  /// Checks the persisted native queue and runs a bounded drain loop if pending
  /// segments or manifests remain. Concurrent callers share the active run.
  Future<PhoneCoreLiveUploadRecoveryResult> recoverPendingUploads() {
    final active = _inFlightRecovery;
    if (active != null) {
      return active;
    }
    final run = _runRecovery();
    late final Future<PhoneCoreLiveUploadRecoveryResult> tracked;
    tracked = run.then((result) {
      _lastResult = result;
      return result;
    }).whenComplete(() {
      if (identical(_inFlightRecovery, tracked)) {
        _inFlightRecovery = null;
      }
    });
    _inFlightRecovery = tracked;
    return tracked;
  }

  Future<PhoneCoreLiveUploadRecoveryResult> _runRecovery() async {
    if (!_isPlatformSupported()) {
      return const PhoneCoreLiveUploadRecoveryResult(
        status: PhoneCoreLiveUploadRecoveryStatus.unavailable,
      );
    }

    final startMs = _nowMs();
    var totalWaited = Duration.zero;
    var drainIterations = 0;
    var totalStepsTaken = 0;
    var hasPendingWork = false;
    int? nextWakeAtMs;
    var pendingSessionCount = 0;
    var pendingSegmentCount = 0;
    var pendingBytes = 0;
    var pendingSessionIds = const <String>[];

    PhoneCoreLiveUploadRecoveryResult buildResult(
      PhoneCoreLiveUploadRecoveryStatus status, {
      String? errorMessage,
    }) {
      return PhoneCoreLiveUploadRecoveryResult(
        status: status,
        drainIterations: drainIterations,
        totalStepsTaken: totalStepsTaken,
        hasPendingWork: hasPendingWork,
        nextWakeAtMs: status == PhoneCoreLiveUploadRecoveryStatus.drained
            ? null
            : nextWakeAtMs,
        pendingSessionCount: pendingSessionCount,
        pendingSegmentCount: pendingSegmentCount,
        pendingBytes: pendingBytes,
        pendingSessionIds: pendingSessionIds,
        errorMessage: errorMessage,
      );
    }

    try {
      final initialPending = await _uploadService.hasPendingWork();
      hasPendingWork = initialPending.hasPendingWork;
      nextWakeAtMs = initialPending.nextWakeAtMs;
      pendingSessionCount = initialPending.pendingSessionCount;
      pendingSegmentCount = initialPending.pendingSegmentCount;
      pendingBytes = initialPending.pendingBytes;
      pendingSessionIds = initialPending.pendingSessionIds;

      if (!hasPendingWork) {
        return buildResult(PhoneCoreLiveUploadRecoveryStatus.idle);
      }

      final initialDelay = _computeBoundedWaitDelay(
        nextWakeAtMs: nextWakeAtMs,
        startMs: startMs,
        totalWaited: totalWaited,
      );
      if (initialDelay == null) {
        return buildResult(PhoneCoreLiveUploadRecoveryStatus.deferred);
      }
      if (initialDelay > Duration.zero) {
        await _sleep(initialDelay);
        totalWaited += initialDelay;
      }

      var consecutiveIdlePasses = 0;
      while (drainIterations < _config.maxDrainIterations) {
        final drain = await _uploadService.drainOnce(
          maxSteps: _config.maxStepsPerDrain,
        );
        drainIterations += 1;
        totalStepsTaken += drain.stepsTaken;
        hasPendingWork = drain.hasPendingWork;
        nextWakeAtMs = drain.nextWakeAtMs;
        pendingSessionCount = drain.pendingSessionCount;
        pendingSegmentCount = drain.pendingSegmentCount;
        pendingBytes = drain.pendingBytes;
        pendingSessionIds = drain.pendingSessionIds;

        if (!hasPendingWork) {
          _log(
            "PhoneCore K3 recovery drained persisted queue in "
            "$drainIterations iteration(s) ($totalStepsTaken step(s)).",
          );
          return buildResult(PhoneCoreLiveUploadRecoveryStatus.drained);
        }

        if (drainIterations >= _config.maxDrainIterations) {
          break;
        }

        if (drain.didWork) {
          consecutiveIdlePasses = 0;
        } else {
          consecutiveIdlePasses += 1;
        }

        final nextWait = _resolveStepWaitDelay(
          didWork: drain.didWork,
          consecutiveIdlePasses: consecutiveIdlePasses,
          nextWakeAtMs: nextWakeAtMs,
          startMs: startMs,
          totalWaited: totalWaited,
        );
        if (nextWait == null) {
          break;
        }
        if (nextWait > Duration.zero) {
          await _sleep(nextWait);
          totalWaited += nextWait;
        }
      }

      _log(
        "PhoneCore K3 recovery deferred remaining work "
        "(sessions=$pendingSessionCount, segments=$pendingSegmentCount, "
        "nextWakeAtMs=$nextWakeAtMs).",
      );
      return buildResult(PhoneCoreLiveUploadRecoveryStatus.deferred);
    } on MissingPluginException catch (error) {
      return buildResult(
        PhoneCoreLiveUploadRecoveryStatus.unavailable,
        errorMessage: error.message ?? error.toString(),
      );
    } on PlatformException catch (error) {
      final message = error.message ?? error.code;
      _log("PhoneCore K3 upload recovery failed: $message");
      return buildResult(
        PhoneCoreLiveUploadRecoveryStatus.failed,
        errorMessage: message,
      );
    } on FormatException catch (error) {
      _log("PhoneCore K3 upload recovery payload error: ${error.message}");
      return buildResult(
        PhoneCoreLiveUploadRecoveryStatus.failed,
        errorMessage: error.message,
      );
    }
  }

  Duration? _computeBoundedWaitDelay({
    required int? nextWakeAtMs,
    required int startMs,
    required Duration totalWaited,
  }) {
    if (nextWakeAtMs == null) {
      return Duration.zero;
    }
    final remainingMs = nextWakeAtMs - _nowMs();
    if (remainingMs <= 0) {
      return Duration.zero;
    }
    final wait = Duration(milliseconds: remainingMs);
    return _fitsWaitBudget(wait, startMs: startMs, totalWaited: totalWaited)
        ? wait
        : null;
  }

  Duration? _resolveStepWaitDelay({
    required bool didWork,
    required int consecutiveIdlePasses,
    required int? nextWakeAtMs,
    required int startMs,
    required Duration totalWaited,
  }) {
    final scheduledWait = _computeBoundedWaitDelay(
      nextWakeAtMs: nextWakeAtMs,
      startMs: startMs,
      totalWaited: totalWaited,
    );
    if (scheduledWait == null) {
      return null;
    }
    if (scheduledWait > Duration.zero) {
      return scheduledWait;
    }
    if (didWork) {
      return Duration.zero;
    }
    if (consecutiveIdlePasses >= 2 ||
        _config.fallbackIdleDelay <= Duration.zero) {
      return null;
    }
    final fallback = _config.fallbackIdleDelay;
    return _fitsWaitBudget(
      fallback,
      startMs: startMs,
      totalWaited: totalWaited,
    )
        ? fallback
        : null;
  }

  bool _fitsWaitBudget(
    Duration wait, {
    required int startMs,
    required Duration totalWaited,
  }) {
    if (wait > _config.maxWakeWaitPerStep) {
      return false;
    }
    final elapsedMs = math.max(0, _nowMs() - startMs);
    final elapsed = Duration(milliseconds: elapsedMs);
    final used = elapsed > totalWaited ? elapsed : totalWaited;
    return used + wait <= _config.maxTotalRecoveryDuration;
  }

  static void _validateConfig(PhoneCoreLiveUploadRecoveryConfig config) {
    if (config.maxStepsPerDrain < PhoneCoreLiveUploadService.minDrainSteps ||
        config.maxStepsPerDrain > PhoneCoreLiveUploadService.maxDrainSteps) {
      throw RangeError.range(
        config.maxStepsPerDrain,
        PhoneCoreLiveUploadService.minDrainSteps,
        PhoneCoreLiveUploadService.maxDrainSteps,
        "config.maxStepsPerDrain",
      );
    }
    if (config.maxDrainIterations < 1) {
      throw RangeError.value(
        config.maxDrainIterations,
        "config.maxDrainIterations",
        "Must be at least 1.",
      );
    }
    if (config.maxTotalRecoveryDuration.isNegative) {
      throw ArgumentError.value(
        config.maxTotalRecoveryDuration,
        "config.maxTotalRecoveryDuration",
        "Must not be negative.",
      );
    }
    if (config.maxWakeWaitPerStep.isNegative) {
      throw ArgumentError.value(
        config.maxWakeWaitPerStep,
        "config.maxWakeWaitPerStep",
        "Must not be negative.",
      );
    }
    if (config.fallbackIdleDelay.isNegative) {
      throw ArgumentError.value(
        config.fallbackIdleDelay,
        "config.fallbackIdleDelay",
        "Must not be negative.",
      );
    }
  }

  static int _defaultNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  static bool _defaultIsPlatformSupported() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
