import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/models/wearable_replay.dart";
import "package:hydracam/services/wearable_replay_bridge_service.dart";
import "package:integration_test/integration_test.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("native wearable replay channel provides mock proof data",
      (tester) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    final service = WearableReplayBridgeService();
    final capabilities = await service.getCapabilities();

    expect(capabilities.channelAvailable, isTrue);
    expect(capabilities.metaDatAvailable, isFalse);
    expect(capabilities.metaMockAvailable, isTrue);
    expect(capabilities.watchMockAvailable, isTrue);
    expect(capabilities.requiresPhysicalMetaHardware, isTrue);
    expect(capabilities.requiresPhysicalWatchHardware, isTrue);
    expect(capabilities.supportsRollingPovFallback, isTrue);
    expect(capabilities.canSimulateWearableReplay, isTrue);
    if (Platform.isAndroid) {
      expect(capabilities.platform, "android");
      expect(capabilities.supportsWatchHaptics, isTrue);
    } else {
      expect(capabilities.platform, "ios");
      expect(capabilities.supportsGlassesAudio, isTrue);
    }

    final reading = await service.pollWatchTelemetry(
      sourceDeviceId: "galaxy-watch4-sim",
    );
    expect(reading.sourceDeviceId, "galaxy-watch4-sim");
    expect(reading.heartRateBpm, isNotNull);
    expect(reading.motionIntensity, greaterThan(0));
    expect(reading.mockReading, isTrue);

    final recordingId = "integration-pov-"
        "${DateTime.now().millisecondsSinceEpoch}";
    final started = await service.startMetaPovCapture(
      MetaPovCaptureRequest(
        sessionGuid: "integration-session",
        participantId: "player-1",
        sourceDeviceId: "rayban-meta-sim",
        pairedHydraCamDeviceId: "phone-1",
        recordingId: recordingId,
        captureMode: PovCaptureMode.rollingHighlight,
      ),
    );
    final stopped = await service.stopMetaPovCapture(recordingId);

    expect(started.recordingId, recordingId);
    expect(stopped.recordingId, recordingId);
    expect(stopped.captureMode, PovCaptureMode.rollingHighlight);
    expect(stopped.hasAudio, isTrue);
    expect(stopped.mockCapture, isTrue);
    expect(File(stopped.mediaPath).existsSync(), isTrue);
    expect(File(stopped.mediaPath).readAsStringSync(), contains(recordingId));

    final sent = await service.sendFeedback(FeedbackEvent(
      feedbackId: "integration-feedback-$recordingId",
      trackId: "integration-feedback-track",
      context: WearableRecordContext.fromLocalTimestamp(
        sessionGuid: "integration-session",
        participantId: "player-1",
        sourceDeviceId: "phone-1",
        pairedHydraCamDeviceId: "phone-1",
        localTimestamp: DateTime.now().toUtc(),
        syncMetadata: SyncMetadata.masterAnchor(at: DateTime.now().toUtc()),
      ),
      channel: FeedbackChannel.watchHaptic,
      trigger: "marker_saved",
      message: "Marker saved",
    ));
    expect(sent, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
