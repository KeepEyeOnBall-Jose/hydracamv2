import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/services/time_sync_service.dart";

void main() {
  group("computeSample", () {
    test("computes offset and round-trip from the four NTP timestamps", () {
      final t0 = DateTime.utc(2026, 1, 1, 0, 0, 0, 0);
      final t1 = DateTime.utc(2026, 1, 1, 0, 0, 1, 100);
      final t2 = DateTime.utc(2026, 1, 1, 0, 0, 1, 200);
      final t3 = DateTime.utc(2026, 1, 1, 0, 0, 0, 300);

      final sample =
          TimeSyncService.computeSample(t0: t0, t1: t1, t2: t2, t3: t3);

      // offset = ((1100) + (900)) / 2 = 1000 ms
      expect(sample.offset, const Duration(milliseconds: 1000));
      // roundTrip = (300) - (100) = 200 ms
      expect(sample.roundTrip, const Duration(milliseconds: 200));
    });
  });

  group("aggregate", () {
    final calibratedAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test("returns null when there are no samples", () {
      expect(TimeSyncService.aggregate([], calibratedAt: calibratedAt), isNull);
    });

    test("returns null when every sample has an impossible round-trip", () {
      final result = TimeSyncService.aggregate(
        const [
          TimeSyncSample(
              offset: Duration(milliseconds: 5),
              roundTrip: Duration(milliseconds: -1)),
        ],
        calibratedAt: calibratedAt,
      );
      expect(result, isNull);
    });

    test("drops high-RTT outliers and picks the minimum-delay offset", () {
      final result = TimeSyncService.aggregate(
        const [
          TimeSyncSample(
              offset: Duration(milliseconds: 1000),
              roundTrip: Duration(milliseconds: 200)),
          TimeSyncSample(
              offset: Duration(milliseconds: 1005),
              roundTrip: Duration(milliseconds: 50)), // min delay -> chosen
          TimeSyncSample(
              offset: Duration(milliseconds: 980),
              roundTrip: Duration(milliseconds: 400)),
          TimeSyncSample(
              offset: Duration(milliseconds: 1002),
              roundTrip: Duration(milliseconds: 60)),
        ],
        calibratedAt: calibratedAt,
      );

      expect(result, isNotNull);
      // median([50,60,200,400]) = 130; threshold = 195 -> keep {50, 60}.
      expect(result!.sampleCount, 2);
      expect(result.offset, const Duration(milliseconds: 1005));
      expect(result.minRoundTrip, const Duration(milliseconds: 50));
      // uncertainty = 50/2 + spread(3)/2 = 25 + 1.5 -> 26 ms
      expect(result.uncertainty.inMilliseconds, 26);
      expect(result.confidence, TimeSyncConfidence.yellow);
      expect(result.calibratedAt, calibratedAt);
    });

    test("classifies a tight, fresh calibration as green", () {
      final result = TimeSyncService.aggregate(
        const [
          TimeSyncSample(
              offset: Duration(milliseconds: 5),
              roundTrip: Duration(milliseconds: 10)),
        ],
        calibratedAt: calibratedAt,
      );

      expect(result!.uncertainty, const Duration(milliseconds: 5));
      expect(result.confidence, TimeSyncConfidence.green);
    });
  });

  group("confidenceFor", () {
    test("green requires tight uncertainty and a fresh calibration", () {
      expect(
        TimeSyncService.confidenceFor(
            const Duration(milliseconds: 20), const Duration(seconds: 10)),
        TimeSyncConfidence.green,
      );
    });

    test("a stale but tight calibration degrades to yellow", () {
      expect(
        TimeSyncService.confidenceFor(
            const Duration(milliseconds: 20), const Duration(seconds: 120)),
        TimeSyncConfidence.yellow,
      );
    });

    test("a too-stale calibration degrades to red", () {
      expect(
        TimeSyncService.confidenceFor(
            const Duration(milliseconds: 20), const Duration(seconds: 121)),
        TimeSyncConfidence.red,
      );
    });

    test("moderate uncertainty is yellow", () {
      expect(
        TimeSyncService.confidenceFor(
            const Duration(milliseconds: 80), Duration.zero),
        TimeSyncConfidence.yellow,
      );
    });

    test("large uncertainty is red", () {
      expect(
        TimeSyncService.confidenceFor(
            const Duration(milliseconds: 150), Duration.zero),
        TimeSyncConfidence.red,
      );
    });
  });

  group("TimeSyncResult", () {
    test("ageAt clamps negative ages to zero", () {
      final result = TimeSyncResult(
        offset: const Duration(milliseconds: 10),
        uncertainty: const Duration(milliseconds: 5),
        minRoundTrip: const Duration(milliseconds: 10),
        sampleCount: 3,
        confidence: TimeSyncConfidence.green,
        calibratedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      expect(result.ageAt(DateTime.utc(2026, 1, 1, 11, 59, 0)), Duration.zero);
    });

    test("toSyncMetadata recomputes confidence with the capture-time age", () {
      final calibratedAt = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final result = TimeSyncResult(
        offset: const Duration(milliseconds: 12),
        uncertainty: const Duration(milliseconds: 20),
        minRoundTrip: const Duration(milliseconds: 30),
        sampleCount: 4,
        confidence: TimeSyncConfidence.green,
        calibratedAt: calibratedAt,
      );

      // Captured 2 minutes later: tight but stale -> yellow.
      final meta = result.toSyncMetadata(calibratedAt.add(
        const Duration(minutes: 2),
      ));
      expect(meta.confidence, TimeSyncConfidence.yellow);
      expect(meta.calibrationAgeMs, const Duration(minutes: 2).inMilliseconds);
      expect(meta.offsetMs, 12);
      expect(meta.minRoundTripMs, 30);
      expect(meta.uncertaintyMs, 20);
      expect(meta.sampleCount, 4);
    });

    test("reports age-aware freshness and usability", () {
      final calibratedAt = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final result = TimeSyncResult(
        offset: const Duration(milliseconds: 12),
        uncertainty: const Duration(milliseconds: 20),
        minRoundTrip: const Duration(milliseconds: 30),
        sampleCount: 4,
        confidence: TimeSyncConfidence.green,
        calibratedAt: calibratedAt,
      );

      expect(result.isFreshAt(calibratedAt.add(const Duration(seconds: 10))),
          isTrue);
      expect(result.isStaleAt(calibratedAt.add(const Duration(seconds: 10))),
          isFalse);
      expect(
        result.confidenceAt(calibratedAt.add(const Duration(seconds: 90))),
        TimeSyncConfidence.yellow,
      );
      expect(result.isUsableAt(calibratedAt.add(const Duration(seconds: 90))),
          isTrue);
      expect(result.isStaleAt(calibratedAt.add(const Duration(seconds: 90))),
          isFalse);
      expect(
        result.confidenceAt(calibratedAt.add(const Duration(seconds: 121))),
        TimeSyncConfidence.red,
      );
      expect(result.isStaleAt(calibratedAt.add(const Duration(seconds: 121))),
          isTrue);
      expect(result.isUsableAt(calibratedAt.add(const Duration(seconds: 121))),
          isFalse);
    });
  });

  group("SyncMetadata serialization", () {
    test("round-trips through JSON", () {
      final original = SyncMetadata(
        offsetMs: 17,
        minRoundTripMs: 42,
        uncertaintyMs: 30,
        confidence: TimeSyncConfidence.yellow,
        sampleCount: 6,
        calibratedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        calibrationAgeMs: 1500,
      );

      final restored = SyncMetadata.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.offsetMs, original.offsetMs);
      expect(restored.minRoundTripMs, original.minRoundTripMs);
      expect(restored.uncertaintyMs, original.uncertaintyMs);
      expect(restored.confidence, original.confidence);
      expect(restored.sampleCount, original.sampleCount);
      expect(restored.calibratedAt, original.calibratedAt);
      expect(restored.calibrationAgeMs, original.calibrationAgeMs);
    });

    test("masterAnchor is a zero-offset green anchor", () {
      final at = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final anchor = SyncMetadata.masterAnchor(at: at);
      expect(anchor.offsetMs, 0);
      expect(anchor.uncertaintyMs, 0);
      expect(anchor.confidence, TimeSyncConfidence.green);
      expect(anchor.calibrationAgeMs, 0);
    });

    test("fromJson returns null for malformed input", () {
      expect(SyncMetadata.fromJson(null), isNull);
      expect(SyncMetadata.fromJson("not a map"), isNull);
      expect(SyncMetadata.fromJson(const {"offsetMs": 1}), isNull);
    });
  });
}
