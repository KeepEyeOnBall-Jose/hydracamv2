import "json_value_parsers.dart";

/// Exposure settings for one recorded clip: the preset, the lock the app
/// requested, and what the sensor actually used near the start and the end.
///
/// The top-level values come from the start snapshot (falling back to the stop
/// snapshot) so consumers can read exposure, ISO and timing without digging
/// into the raw platform maps.
class RecordingExposureMetadata {
  const RecordingExposureMetadata({
    required this.preset,
    required this.lockStatus,
    this.requestedExposureTimeNs,
    this.exposureTimeNs,
    this.iso,
    this.frameDurationNs,
    this.framesPerSecond,
    this.rollingShutterSkewNs,
    this.underexposed,
    this.source,
    this.lock,
    this.start,
    this.stop,
  });

  /// [ExposurePreset.storageValue] chosen for the clip.
  final String preset;

  /// "locked", "auto", "unsupported", "no_camera", "error" or "unavailable".
  final String lockStatus;
  final int? requestedExposureTimeNs;
  final int? exposureTimeNs;
  final int? iso;
  final int? frameDurationNs;
  final double? framesPerSecond;

  /// Sensor readout time from first to last row; null where the platform does
  /// not report it (AVFoundation).
  final int? rollingShutterSkewNs;

  /// True when the metered ISO needed for the shutter exceeded the sensor max.
  final bool? underexposed;
  final String? source;
  final Map<String, dynamic>? lock;
  final Map<String, dynamic>? start;
  final Map<String, dynamic>? stop;

  bool get isLocked => lockStatus == "locked";

  static RecordingExposureMetadata fromSnapshots({
    required String preset,
    required String lockStatus,
    int? requestedExposureTimeNs,
    Map<String, dynamic>? lock,
    Map<String, dynamic>? start,
    Map<String, dynamic>? stop,
  }) {
    final primary = _usableSnapshot(start) ?? _usableSnapshot(stop);
    return RecordingExposureMetadata(
      preset: preset,
      lockStatus: lockStatus,
      requestedExposureTimeNs: requestedExposureTimeNs,
      exposureTimeNs: toIntOrNull(primary?["exposureTimeNs"]),
      iso: toIntOrNull(primary?["iso"]),
      frameDurationNs: toIntOrNull(primary?["frameDurationNs"]),
      framesPerSecond: toDoubleOrNull(primary?["fps"]),
      rollingShutterSkewNs: toIntOrNull(primary?["rollingShutterSkewNs"]),
      underexposed:
          lock?["underexposed"] is bool ? lock!["underexposed"] as bool : null,
      source: primary?["source"]?.toString(),
      lock: lock,
      start: start,
      stop: stop,
    );
  }

  static RecordingExposureMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final preset = json["preset"]?.toString();
    if (preset == null || preset.isEmpty) {
      return null;
    }
    return RecordingExposureMetadata(
      preset: preset,
      lockStatus: json["lockStatus"]?.toString() ?? "unavailable",
      requestedExposureTimeNs: toIntOrNull(json["requestedExposureTimeNs"]),
      exposureTimeNs: toIntOrNull(json["exposureTimeNs"]),
      iso: toIntOrNull(json["iso"]),
      frameDurationNs: toIntOrNull(json["frameDurationNs"]),
      framesPerSecond: toDoubleOrNull(json["fps"]),
      rollingShutterSkewNs: toIntOrNull(json["rollingShutterSkewNs"]),
      underexposed:
          json["underexposed"] is bool ? json["underexposed"] as bool : null,
      source: json["source"]?.toString(),
      lock: toStringKeyedMap(json["lock"]),
      start: toStringKeyedMap(json["start"]),
      stop: toStringKeyedMap(json["stop"]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "preset": preset,
      "lockStatus": lockStatus,
      "requestedExposureTimeNs": requestedExposureTimeNs,
      "exposureTimeNs": exposureTimeNs,
      "iso": iso,
      "frameDurationNs": frameDurationNs,
      "fps": framesPerSecond,
      "rollingShutterSkewNs": rollingShutterSkewNs,
      if (underexposed != null) "underexposed": underexposed,
      if (source != null) "source": source,
      if (lock != null) "lock": lock,
      if (start != null) "start": start,
      if (stop != null) "stop": stop,
    };
  }

  static Map<String, dynamic>? _usableSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null || snapshot["status"] != "ok") {
      return null;
    }
    return snapshot;
  }
}
