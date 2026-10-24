import "package:flutter/services.dart";

import "../models/camera_capture_settings.dart";
import "../models/json_value_parsers.dart";
import "../models/recording_exposure_metadata.dart";

/// Client for the native manual exposure channel (Camera2 interop on Android,
/// AVFoundation on iOS). Every call degrades to null when the platform side is
/// missing, so capture never fails because of exposure control.
class ManualExposureService {
  ManualExposureService({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel =
      MethodChannel("hydracamv2/manual_exposure");

  final MethodChannel _channel;

  /// Locks exposure time, metered ISO, white balance and focus on [cameraName]
  /// (the Flutter camera description name).
  Future<Map<String, dynamic>?> applyLock({
    required String cameraName,
    required int exposureTimeNs,
    required int frameDurationNs,
  }) {
    return _invoke("applyLock", {
      "cameraName": cameraName,
      "exposureTimeNs": exposureTimeNs,
      "frameDurationNs": frameDurationNs,
    });
  }

  Future<Map<String, dynamic>?> release({required String cameraName}) {
    return _invoke("release", {"cameraName": cameraName});
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

  Future<void> lockBeforeStart() async {
    final exposureTimeNs = preset.exposureTimeNs;
    if (exposureTimeNs == null) {
      _lockStatus = "auto";
      return;
    }
    _lock = await _applyLock(exposureTimeNs);
    _lockStatus = _lock?["status"]?.toString() ?? "unavailable";
  }

  /// Starting a recording reconfigures the capture session on Android, so the
  /// lock is applied again before sampling what the sensor uses.
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
    await abort();
    return RecordingExposureMetadata.fromSnapshots(
      preset: preset.storageValue,
      lockStatus: _lockStatus,
      requestedExposureTimeNs: preset.exposureTimeNs,
      lock: _lock,
      start: start,
      stop: _stopSnapshot,
    );
  }

  /// Restores the camera's previous auto modes. Safe to call more than once.
  Future<void> abort() async {
    if (!isLocked || _released) {
      return;
    }
    _released = true;
    await _service.release(cameraName: cameraName);
  }

  bool _released = false;

  Future<Map<String, dynamic>?> _sampleAfterStart() async {
    final exposureTimeNs = preset.exposureTimeNs;
    if (isLocked && exposureTimeNs != null) {
      final relock = await _applyLock(exposureTimeNs);
      final relockStatus = relock?["status"]?.toString() ?? "unavailable";
      _lock = {...?_lock, "relockAfterStartStatus": relockStatus};
    }
    await Future<void>.delayed(settleDelay);
    return _service.readCaptureSettings(cameraName: cameraName);
  }

  Future<Map<String, dynamic>?> _applyLock(int exposureTimeNs) {
    return _service.applyLock(
      cameraName: cameraName,
      exposureTimeNs: exposureTimeNs,
      frameDurationNs: frameDurationNs,
    );
  }
}
