import "package:flutter/foundation.dart";

import "../constants.dart";
import "../models/sync_metadata.dart";

/// One round-trip measurement against the master clock.
class TimeSyncSample {
  /// Estimated clock offset (master - local) for this exchange.
  final Duration offset;

  /// Measured round-trip delay for this exchange.
  final Duration roundTrip;

  const TimeSyncSample({required this.offset, required this.roundTrip});
}

/// Aggregated calibration of this device's clock against the master clock.
class TimeSyncResult {
  /// Best estimate of (master - local) clock offset.
  final Duration offset;

  /// Estimated uncertainty of [offset].
  final Duration uncertainty;

  /// Minimum round-trip delay observed in the calibration burst.
  final Duration minRoundTrip;

  /// Number of usable samples behind this calibration.
  final int sampleCount;

  /// Confidence tier at the moment of calibration.
  final TimeSyncConfidence confidence;

  /// When this calibration was produced.
  final DateTime calibratedAt;

  const TimeSyncResult({
    required this.offset,
    required this.uncertainty,
    required this.minRoundTrip,
    required this.sampleCount,
    required this.confidence,
    required this.calibratedAt,
  });

  /// Age of this calibration relative to [now].
  Duration ageAt(DateTime now) {
    final age = now.difference(calibratedAt);
    return age.isNegative ? Duration.zero : age;
  }

  /// Builds a per-capture [SyncMetadata] snapshot, recomputing confidence with
  /// the calibration age at the capture instant [at].
  SyncMetadata toSyncMetadata(DateTime at) {
    final age = ageAt(at);
    return SyncMetadata(
      offsetMs: offset.inMilliseconds,
      minRoundTripMs: minRoundTrip.inMilliseconds,
      uncertaintyMs: uncertainty.inMilliseconds,
      confidence: TimeSyncService.confidenceFor(uncertainty, age),
      sampleCount: sampleCount,
      calibratedAt: calibratedAt,
      calibrationAgeMs: age.inMilliseconds,
    );
  }

  TimeSyncConfidence confidenceAt(DateTime now) {
    return TimeSyncService.confidenceFor(uncertainty, ageAt(now));
  }

  bool isFreshAt(DateTime now) {
    return confidenceAt(now) == TimeSyncConfidence.green;
  }

  bool isStaleAt(DateTime now) {
    return ageAt(now).inSeconds > timeSyncStaleSeconds;
  }

  bool isUsableAt(DateTime now) {
    return confidenceAt(now) != TimeSyncConfidence.red;
  }

  Map<String, dynamic> toJson() {
    return {
      "offsetMs": offset.inMilliseconds,
      "uncertaintyMs": uncertainty.inMilliseconds,
      "minRoundTripMs": minRoundTrip.inMilliseconds,
      "sampleCount": sampleCount,
      "confidence": confidence.name,
      "calibratedAt": calibratedAt.toIso8601String(),
    };
  }
}

/// Computes and holds the latest NTP-style clock calibration against the master.
///
/// The synchronization math is intentionally pure and side-effect free so it can
/// be unit-tested without any networking. The singleton only adds a
/// [ValueNotifier] so the UI and the capture path can read the most recent
/// calibration.
class TimeSyncService {
  static final TimeSyncService _instance = TimeSyncService();

  static TimeSyncService get instance => _instance;

  /// Most recent calibration, or `null` if the device has never synchronized.
  final ValueNotifier<TimeSyncResult?> latest =
      ValueNotifier<TimeSyncResult?>(null);

  void record(TimeSyncResult result) {
    latest.value = result;
  }

  void reset() {
    latest.value = null;
  }

  /// Computes a single sample from the four NTP timestamps:
  /// - [t0] local send time, [t1] master receive time,
  /// - [t2] master send time, [t3] local receive time.
  ///
  /// `offset = ((t1 - t0) + (t2 - t3)) / 2`
  /// `roundTrip = (t3 - t0) - (t2 - t1)`
  static TimeSyncSample computeSample({
    required DateTime t0,
    required DateTime t1,
    required DateTime t2,
    required DateTime t3,
  }) {
    final offsetUs =
        (t1.difference(t0).inMicroseconds + t2.difference(t3).inMicroseconds) ~/
            2;
    final roundTripUs =
        t3.difference(t0).inMicroseconds - t2.difference(t1).inMicroseconds;
    return TimeSyncSample(
      offset: Duration(microseconds: offsetUs),
      roundTrip: Duration(microseconds: roundTripUs),
    );
  }

  /// Aggregates a burst of [samples] into a single calibration.
  ///
  /// Samples with an impossible (negative) round-trip are discarded, then
  /// samples whose round-trip exceeds `median * timeSyncOutlierFactor` are
  /// dropped. The minimum-delay sample's offset is taken as the estimate
  /// (standard NTP best-sample selection); uncertainty combines that sample's
  /// half-round-trip with the offset spread of the kept samples.
  ///
  /// Returns `null` when no usable samples remain.
  static TimeSyncResult? aggregate(
    List<TimeSyncSample> samples, {
    required DateTime calibratedAt,
  }) {
    final usable = samples
        .where((sample) => !sample.roundTrip.isNegative)
        .toList()
      ..sort((a, b) =>
          a.roundTrip.inMicroseconds.compareTo(b.roundTrip.inMicroseconds));
    if (usable.isEmpty) {
      return null;
    }

    final medianUs = _medianMicros(usable);
    final thresholdUs = (medianUs * timeSyncOutlierFactor).round();
    final kept = usable
        .where((sample) => sample.roundTrip.inMicroseconds <= thresholdUs)
        .toList();
    if (kept.isEmpty) {
      kept.add(usable.first);
    }

    // usable was sorted ascending by round-trip, so the first kept sample has
    // the minimum delay.
    final chosen = kept.first;

    var minOffsetUs = kept.first.offset.inMicroseconds;
    var maxOffsetUs = kept.first.offset.inMicroseconds;
    for (final sample in kept) {
      final us = sample.offset.inMicroseconds;
      if (us < minOffsetUs) minOffsetUs = us;
      if (us > maxOffsetUs) maxOffsetUs = us;
    }
    final spreadUs = maxOffsetUs - minOffsetUs;
    final uncertaintyUs =
        (chosen.roundTrip.inMicroseconds ~/ 2) + (spreadUs ~/ 2);
    final uncertainty = Duration(microseconds: uncertaintyUs);

    return TimeSyncResult(
      offset: chosen.offset,
      uncertainty: uncertainty,
      minRoundTrip: chosen.roundTrip,
      sampleCount: kept.length,
      confidence: confidenceFor(uncertainty, Duration.zero),
      calibratedAt: calibratedAt,
    );
  }

  /// Classifies a calibration into a confidence tier given its [uncertainty]
  /// and [age].
  static TimeSyncConfidence confidenceFor(Duration uncertainty, Duration age) {
    final uncertaintyMs = uncertainty.inMilliseconds;
    if (age.inSeconds > timeSyncStaleSeconds) {
      return TimeSyncConfidence.red;
    }
    if (uncertaintyMs <= timeSyncGreenUncertaintyMs &&
        age.inSeconds <= timeSyncFreshSeconds) {
      return TimeSyncConfidence.green;
    }
    if (uncertaintyMs <= timeSyncYellowUncertaintyMs) {
      return TimeSyncConfidence.yellow;
    }
    return TimeSyncConfidence.red;
  }

  static int _medianMicros(List<TimeSyncSample> sortedAscending) {
    final n = sortedAscending.length;
    final mid = n ~/ 2;
    if (n.isOdd) {
      return sortedAscending[mid].roundTrip.inMicroseconds;
    }
    final lower = sortedAscending[mid - 1].roundTrip.inMicroseconds;
    final upper = sortedAscending[mid].roundTrip.inMicroseconds;
    return (lower + upper) ~/ 2;
  }
}
