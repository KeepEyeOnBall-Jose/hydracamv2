import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/models/wearable_replay.dart";

void main() {
  group("Wearable replay models", () {
    test("sample serializes shared-clock timestamp and sync confidence", () {
      final sync = SyncMetadata(
        offsetMs: 42,
        minRoundTripMs: 8,
        uncertaintyMs: 12,
        confidence: TimeSyncConfidence.green,
        sampleCount: 8,
        calibratedAt: DateTime.utc(2026, 6, 22, 10),
        calibrationAgeMs: 1000,
      );
      final localTimestamp = DateTime.utc(2026, 6, 22, 10, 0, 5);
      final context = WearableRecordContext.fromLocalTimestamp(
        sessionGuid: "session-1",
        participantId: "player-1",
        sourceDeviceId: "galaxy-watch-4",
        pairedHydraCamDeviceId: "phone-1",
        localTimestamp: localTimestamp,
        syncMetadata: sync,
      );
      final sample = WearableSample(
        sampleId: "sample-1",
        trackId: "watch-track",
        context: context,
        heartRateBpm: 151,
        accelerometerX: 1.2,
        accelerometerY: -0.4,
        accelerometerZ: 9.6,
        motionIntensity: 0.82,
      );

      final json = sample.toJson();
      final parsed = WearableSample.fromJson(json);

      expect(json["sharedClockTimestamp"], "2026-06-22T10:00:05.042Z");
      expect(json["syncConfidence"], "green");
      expect(json["heartRateBpm"], 151);
      expect(parsed.context.syncMetadata.offsetMs, 42);
      expect(
          parsed.context.sharedClockTimestamp,
          localTimestamp.add(
            const Duration(milliseconds: 42),
          ));
      expect(parsed.motionIntensity, 0.82);
    });

    test("POV recording defaults to audio-on publish review", () {
      final sync = SyncMetadata.masterAnchor(
        at: DateTime.utc(2026, 6, 22, 10),
      );
      final context = WearableRecordContext.fromLocalTimestamp(
        sessionGuid: "session-1",
        participantId: "player-1",
        sourceDeviceId: "rayban-meta",
        pairedHydraCamDeviceId: "iphone-1",
        localTimestamp: DateTime.utc(2026, 6, 22, 10, 1),
        syncMetadata: sync,
      );
      final recording = PovRecording(
        recordingId: "pov-1",
        trackId: "pov-track",
        context: context,
        mediaPath: "/tmp/pov-1.mp4",
        captureMode: PovCaptureMode.continuous,
        startedAt: DateTime.utc(2026, 6, 22, 10, 1),
        endedAt: DateTime.utc(2026, 6, 22, 10, 6),
        hasAudio: true,
      );

      final json = recording.toJson();
      final parsed = PovRecording.fromJson(json);

      expect(json["audioPublishDefault"], isTrue);
      expect(json["reviewRequired"], isTrue);
      expect(parsed.captureMode, PovCaptureMode.continuous);
      expect(parsed.hasAudio, isTrue);
    });

    test("sync calibration records clap-flash alignment target", () {
      final sync = SyncMetadata(
        offsetMs: 8,
        minRoundTripMs: 6,
        uncertaintyMs: 9,
        confidence: TimeSyncConfidence.green,
        sampleCount: 8,
        calibratedAt: DateTime.utc(2026, 6, 22, 9, 59, 55),
        calibrationAgeMs: 5000,
      );
      final context = WearableRecordContext.fromLocalTimestamp(
        sessionGuid: "session-1",
        participantId: "player-1",
        sourceDeviceId: "phone-1",
        pairedHydraCamDeviceId: "phone-1",
        localTimestamp: DateTime.utc(2026, 6, 22, 10),
        syncMetadata: sync,
      );
      final calibration = WearableSyncCalibration(
        calibrationId: "calibration-1",
        context: context,
        ritual: "clap_flash",
        observedSourceDeviceIds: const [
          "phone-1",
          "rayban-meta",
          "galaxy-watch4",
        ],
        targetAlignmentMs: 50,
        measuredAlignmentErrorMs: 31,
        performedAt: DateTime.utc(2026, 6, 22, 10),
      );

      final json = calibration.toJson();
      final parsed = WearableSyncCalibration.fromJson(json);

      expect(json["recordType"], "wearableSyncCalibration");
      expect(json["ritual"], "clap_flash");
      expect(json["targetAlignmentMs"], 50);
      expect(json["measuredAlignmentErrorMs"], 31);
      expect(json["withinTarget"], isTrue);
      expect(json["syncConfidence"], "green");
      expect(parsed.observedSourceDeviceIds, [
        "phone-1",
        "rayban-meta",
        "galaxy-watch4",
      ]);
      expect(parsed.withinTarget, isTrue);
    });
  });
}
