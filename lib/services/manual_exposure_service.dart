import "package:flutter/services.dart";
import "package:uuid/uuid.dart";

import "../models/camera_capture_settings.dart";
import "../models/json_value_parsers.dart";
import "../models/recording_exposure_metadata.dart";

/// Client for the native manual exposure channel (Camera2 interop on Android,
/// AVFoundation on iOS). Every call degrades to null when the platform side is
/// missing. Unresolved native mutations retain their owner so a later capture
/// cannot silently inherit unknown settings.
class ManualExposureService {
  ManualExposureService({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel =
      MethodChannel("hydracamv2/manual_exposure");

  final MethodChannel _channel;

  /// Locks exposure time, metered ISO, white balance and focus on [cameraName]
  /// (the Flutter camera description name).
  Future<Map<String, dynamic>?> applyLock({
    required String ownerId,
    required String cameraName,
    required int exposureTimeNs,
    required int frameDurationNs,
  }) {
    return _invoke("applyLock", {
      "ownerId": ownerId,
      "cameraName": cameraName,
      "exposureTimeNs": exposureTimeNs,
      "frameDurationNs": frameDurationNs,
    });
  }

  Future<Map<String, dynamic>?> release({
    required String cameraName,
    required String ownerId,
  }) {
    return _invoke("release", {"cameraName": cameraName, "ownerId": ownerId});
  }

  /// Values the sensor used for the latest frame.
  Future<Map<String, dynamic>?> readCaptureSettings({
    required String cameraName,
  }) {
    return _invoke("readCaptureSettings", {"cameraName": cameraName});
  }

  Future<Map<String, dynamic>?> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      return toStringKeyedMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      return {
        "status": "error",
        "error": error.message ?? error.code,
      };
    }
  }
}

/// Exposure lifecycle of one recording:
/// [lockBeforeStart] -> start recording -> [afterStart] -> [readBeforeStop]
/// -> stop recording -> [finish]. Call [abort] if the recording never started.
class RecordingExposureSession {
  RecordingExposureSession({
    required ManualExposureService service,
    required this.preset,
    required this.cameraName,
    required this.frameDurationNs,
    this.settleDelay = const Duration(milliseconds: 500),
    this.snapshotTimeout = const Duration(seconds: 2),
  }) : _service = service;

  final ManualExposureService _service;
  final ExposurePreset preset;
  final String cameraName;
  final int frameDurationNs;
  final String ownerId = const Uuid().v4();

  /// Wait after recording starts before sampling, so the sample reflects the
  /// recording session rather than the preview it replaced.
  final Duration settleDelay;
  final Duration snapshotTimeout;

  String _lockStatus = "unavailable";
  Map<String, dynamic>? _lock;
  Future<Map<String, dynamic>?>? _startSnapshot;
  Map<String, dynamic>? _stopSnapshot;

  String get lockStatus => _lockStatus;
  bool get isLocked => _lockStatus == "locked";
  bool get cleanupPending => _needsRelease || mutationPending;
  bool get mutationPending => _pendingApply != null;

  Future<void> lockBeforeStart() async {
    final exposureTimeNs = preset.exposureTimeNs;
    if (exposureTimeNs == null) {
      _lockStatus = "auto";
      return;
    }
    _lock = await _applyLock(exposureTimeNs);
    _lockStatus = _lock?["status"]?.toString() ?? "unavailable";
    _needsRelease = _needsRelease || isLocked;
  }

  /// Confirm the same owner's lock after recording starts before sampling.
  /// CameraX retains request options across ordinary use-case transitions;
  /// this confirmation is not evidence of an earlier automatic-exposure gap.
  void afterStart() {
    _startSnapshot = _sampleAfterStart();
  }

  Future<void> readBeforeStop() async {
    _stopSnapshot = await _service
        .readCaptureSettings(cameraName: cameraName)
        .timeout(snapshotTimeout, onTimeout: () => {"status": "timeout"});
  }

  Future<RecordingExposureMetadata> finish() async {
    final start = await (_startSnapshot ?? Future.value(null))
        .timeout(snapshotTimeout, onTimeout: () => {"status": "timeout"});
    // Cleanup may await native work while a timed-out relock completes. Keep
    // the recording status observed at the snapshot deadline.
    final recordingLockStatus = _lockStatus;
    await abort().timeout(snapshotTimeout, onTimeout: () {
      _lock = {...?_lock, "releaseStatus": "pending"};
    });
    return RecordingExposureMetadata.fromSnapshots(
      preset: preset.storageValue,
      lockStatus: recordingLockStatus,
      requestedExposureTimeNs: preset.exposureTimeNs,
      lock: _lock,
      start: start,
      stop: _stopSnapshot,
    );
  }

  /// Attempts to restore the camera's previous auto modes. Concurrent callers
  /// share settlement; a failed acknowledgement remains eligible for retry.
  Future<void> abort() {
    _cleanupRequested = true;
    if (!cleanupPending) {
      return Future<void>.value();
    }
    return _releaseFuture ??= _release();
  }

  bool _needsRelease = false;
  bool _cleanupRequested = false;
  Future<Map<String, dynamic>?>? _pendingApply;
  Future<void>? _releaseFuture;

  Future<void> _release() async {
    try {
      final applying = _pendingApply;
      if (applying != null) {
        try {
          await applying;
        } catch (_) {
          // The initial caller observes the error. An uncertain mutation
          // still needs its original owner's restoration attempt.
        }
      }
      if (!_needsRelease) {
        return;
      }
      final result =
          await _service.release(cameraName: cameraName, ownerId: ownerId);
      final status = result?["status"]?.toString() ?? "unavailable";
      _lock = {...?_lock, "releaseStatus": status};
      if (status == "released") {
        _needsRelease = false;
      }
    } finally {
      _releaseFuture = null;
    }
  }

  Future<Map<String, dynamic>?> _sampleAfterStart() async {
    if (_cleanupRequested) {
      return null;
    }
    final exposureTimeNs = preset.exposureTimeNs;
    if (isLocked && exposureTimeNs != null) {
      // A preview acknowledgement does not establish that this relock has
      // succeeded. Keep cleanup eligibility separately from recording truth.
      _lockStatus = "unavailable";
      final relock = await _applyLock(exposureTimeNs);
      final relockStatus = relock?["status"]?.toString() ?? "unavailable";
      _lockStatus = relockStatus;
      _lock = {...?_lock, "relockAfterStartStatus": relockStatus};
    }
    await Future<void>.delayed(settleDelay);
    return _service.readCaptureSettings(cameraName: cameraName);
  }

  Future<Map<String, dynamic>?> _applyLock(int exposureTimeNs) {
    late final Future<Map<String, dynamic>?> applying;
    applying = Future<Map<String, dynamic>?>.sync(() => _service.applyLock(
          ownerId: ownerId,
          cameraName: cameraName,
          exposureTimeNs: exposureTimeNs,
          frameDurationNs: frameDurationNs,
        )).then((result) {
      final status = result?["status"]?.toString();
      _needsRelease = _needsRelease ||
          status == "locked" ||
          status == "busy" ||
          result?["cleanupRequired"] == true ||
          (status == "error" && result?["cleanupRequired"] != false);
      return result;
    }, onError: (Object error, StackTrace stack) {
      _needsRelease = true;
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      if (identical(_pendingApply, applying)) {
        _pendingApply = null;
      }
    });
    _pendingApply = applying;
    return applying;
  }
}
