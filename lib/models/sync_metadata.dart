/// Confidence tier for a clock-synchronization calibration.
///
/// Mirrors the green/yellow/red contract from the NTP sync specification:
/// - [green]: tight uncertainty and a fresh calibration.
/// - [yellow]: usable but degraded; alignment should be treated cautiously.
/// - [red]: no usable calibration; clips should not be trusted for strict sync.
enum TimeSyncConfidence { green, yellow, red }

TimeSyncConfidence timeSyncConfidenceFromName(String? name) {
  switch (name) {
    case "green":
      return TimeSyncConfidence.green;
    case "yellow":
      return TimeSyncConfidence.yellow;
    default:
      return TimeSyncConfidence.red;
  }
}

/// Per-capture snapshot of the device's clock-sync quality at the moment a
/// photo or video was captured.
///
/// This is the in-app, serializable form of a calibration result. It is stored
/// inside the session `metadata.json` and also written next to each media file
/// as a `<media>.sync.json` sidecar so a later import/sync tool can reject
/// weakly-synchronized clips.
class SyncMetadata {
  /// Estimated offset of this device's clock relative to the shared master
  /// clock, in milliseconds. Positive means the master clock is ahead.
  final int offsetMs;

  /// Minimum measured round-trip time across the calibration burst, in
  /// milliseconds.
  final int minRoundTripMs;

  /// Estimated uncertainty of [offsetMs], in milliseconds.
  final int uncertaintyMs;

  /// Confidence tier, recomputed with the calibration age at capture time.
  final TimeSyncConfidence confidence;

  /// Number of usable samples that produced the calibration.
  final int sampleCount;

  /// When the calibration was produced.
  final DateTime calibratedAt;

  /// Age of the calibration at the moment of capture, in milliseconds.
  final int calibrationAgeMs;

  const SyncMetadata({
    required this.offsetMs,
    required this.minRoundTripMs,
    required this.uncertaintyMs,
    required this.confidence,
    required this.sampleCount,
    required this.calibratedAt,
    required this.calibrationAgeMs,
  });

  /// Anchor metadata for the reference device (the master). The master defines
  /// the shared clock, so its offset and uncertainty are zero by definition.
  factory SyncMetadata.masterAnchor({required DateTime at}) {
    return SyncMetadata(
      offsetMs: 0,
      minRoundTripMs: 0,
      uncertaintyMs: 0,
      confidence: TimeSyncConfidence.green,
      sampleCount: 0,
      calibratedAt: at,
      calibrationAgeMs: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "offsetMs": offsetMs,
      "minRoundTripMs": minRoundTripMs,
      "uncertaintyMs": uncertaintyMs,
      "confidence": confidence.name,
      "sampleCount": sampleCount,
      "calibratedAt": calibratedAt.toIso8601String(),
      "calibrationAgeMs": calibrationAgeMs,
    };
  }

  static SyncMetadata? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final calibratedAtRaw = value["calibratedAt"];
    final calibratedAt =
        calibratedAtRaw is String ? DateTime.tryParse(calibratedAtRaw) : null;
    if (calibratedAt == null) {
      return null;
    }
    int asInt(Object? raw) => raw is num ? raw.round() : 0;
    return SyncMetadata(
      offsetMs: asInt(value["offsetMs"]),
      minRoundTripMs: asInt(value["minRoundTripMs"]),
      uncertaintyMs: asInt(value["uncertaintyMs"]),
      confidence: timeSyncConfidenceFromName(value["confidence"]?.toString()),
      sampleCount: asInt(value["sampleCount"]),
      calibratedAt: calibratedAt,
      calibrationAgeMs: asInt(value["calibrationAgeMs"]),
    );
  }
}
