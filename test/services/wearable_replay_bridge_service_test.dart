import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/models/wearable_replay.dart";
import "package:hydracam/services/wearable_replay_bridge_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("hydracamv2/wearable_replay_test");

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test("getCapabilities maps wearable replay native mock support", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "getCapabilities");
      return {
        "platform": "android",
        "channelAvailable": true,
        "metaDatAvailable": false,
        "metaMockAvailable": true,
        "watchCompanionAvailable": false,
        "watchMockAvailable": true,
        "supportsWatchHaptics": true,
        "supportsGlassesAudio": true,
        "supportsRollingPovFallback": true,
        "requiresPhysicalMetaHardware": true,
        "requiresPhysicalWatchHardware": true,
        "reason": "Mock wearable replay support is available.",
      };
    });

    final service = WearableReplayBridgeService(channel: channel);

    final capabilities = await service.getCapabilities();

    expect(capabilities.platform, "android");
    expect(capabilities.channelAvailable, isTrue);
    expect(capabilities.metaDatAvailable, isFalse);
    expect(capabilities.metaMockAvailable, isTrue);
    expect(capabilities.watchCompanionAvailable, isFalse);
    expect(capabilities.watchMockAvailable, isTrue);
    expect(capabilities.supportsWatchHaptics, isTrue);
    expect(capabilities.supportsGlassesAudio, isTrue);
    expect(capabilities.supportsRollingPovFallback, isTrue);
    expect(capabilities.requiresPhysicalMetaHardware, isTrue);
    expect(capabilities.requiresPhysicalWatchHardware, isTrue);
    expect(capabilities.canSimulateWearableReplay, isTrue);
  });

  test("getCapabilities reports unsupported when native channel is missing",
      () async {
    final service = WearableReplayBridgeService(channel: channel);

    final capabilities = await service.getCapabilities();

    expect(capabilities.platform, "unknown");
    expect(capabilities.channelAvailable, isFalse);
    expect(capabilities.canSimulateWearableReplay, isFalse);
    expect(capabilities.reason, contains("not available"));
  });

  test("pollWatchTelemetry maps HR and motion data", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "pollWatchTelemetry");
      expect(call.arguments, {"sourceDeviceId": "galaxy-watch4-sim"});
      return {
        "sourceDeviceId": "galaxy-watch4-sim",
        "localTimestamp": "2026-06-22T12:00:01.000Z",
        "heartRateBpm": 151,
        "interBeatIntervalMs": 397,
        "accelerometerX": 0.31,
        "accelerometerY": 0.42,
        "accelerometerZ": 9.62,
        "gyroscopeX": 0.11,
        "gyroscopeY": 0.07,
        "gyroscopeZ": 0.13,
        "motionIntensity": 0.76,
        "mockReading": true,
      };
    });

    final service = WearableReplayBridgeService(channel: channel);

    final reading = await service.pollWatchTelemetry(
      sourceDeviceId: "galaxy-watch4-sim",
    );

    expect(reading.sourceDeviceId, "galaxy-watch4-sim");
    expect(reading.localTimestamp, DateTime.parse("2026-06-22T12:00:01.000Z"));
    expect(reading.heartRateBpm, 151);
    expect(reading.interBeatIntervalMs, 397);
    expect(reading.accelerometerZ, 9.62);
    expect(reading.gyroscopeX, 0.11);
    expect(reading.motionIntensity, 0.76);
    expect(reading.mockReading, isTrue);
  });

  test("starts and stops Meta POV capture through the native bridge", () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == "startMetaPovCapture") {
        expect(call.arguments, {
          "sessionGuid": "session-1",
          "participantId": "player-1",
          "sourceDeviceId": "rayban-meta-sim",
          "pairedHydraCamDeviceId": "phone-1",
          "recordingId": "pov-player-1",
          "captureMode": "continuous",
          "includeAudio": true,
          "targetDurationSeconds": 30,
        });
        return {
          "recordingId": "pov-player-1",
          "mediaPath": "/tmp/pov-player-1.mp4",
          "startedAt": "2026-06-22T12:00:00.000Z",
          "endedAt": "2026-06-22T12:00:00.000Z",
          "captureMode": "continuous",
          "hasAudio": true,
          "mockCapture": true,
        };
      }
      if (call.method == "stopMetaPovCapture") {
        expect(call.arguments, {"recordingId": "pov-player-1"});
        return {
          "recordingId": "pov-player-1",
          "mediaPath": "/tmp/pov-player-1.mp4",
          "startedAt": "2026-06-22T12:00:00.000Z",
          "endedAt": "2026-06-22T12:00:08.000Z",
          "captureMode": "continuous",
          "hasAudio": true,
          "mockCapture": true,
        };
      }
      fail("Unexpected method ${call.method}");
    });

    final service = WearableReplayBridgeService(channel: channel);

    final started = await service.startMetaPovCapture(
      const MetaPovCaptureRequest(
        sessionGuid: "session-1",
        participantId: "player-1",
        sourceDeviceId: "rayban-meta-sim",
        pairedHydraCamDeviceId: "phone-1",
        recordingId: "pov-player-1",
      ),
    );
    final stopped = await service.stopMetaPovCapture("pov-player-1");

    expect(started.recordingId, "pov-player-1");
    expect(started.captureMode, PovCaptureMode.continuous);
    expect(started.hasAudio, isTrue);
    expect(started.mockCapture, isTrue);
    expect(stopped.endedAt, DateTime.parse("2026-06-22T12:00:08.000Z"));
    expect(calls, ["startMetaPovCapture", "stopMetaPovCapture"]);
  });

  test("sendFeedback passes publish-scoped feedback events to native",
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "sendFeedback");
      final payload = call.arguments as Map<dynamic, dynamic>;
      expect(payload["recordType"], "feedbackEvent");
      expect(payload["feedbackId"], "feedback-1");
      expect(payload["sessionGuid"], "session-1");
      expect(payload["channel"], "watchHaptic");
      expect(payload["publishConsent"], isTrue);
      return true;
    });

    final service = WearableReplayBridgeService(channel: channel);

    final sent = await service.sendFeedback(FeedbackEvent(
      feedbackId: "feedback-1",
      trackId: "feedback-player-1",
      context: WearableRecordContext.fromLocalTimestamp(
        sessionGuid: "session-1",
        participantId: "player-1",
        sourceDeviceId: "phone-1",
        pairedHydraCamDeviceId: "phone-1",
        localTimestamp: DateTime.utc(2026, 6, 22, 12),
        syncMetadata: SyncMetadata.masterAnchor(
          at: DateTime.utc(2026, 6, 22, 12),
        ),
      ),
      channel: FeedbackChannel.watchHaptic,
      trigger: "marker_saved",
      message: "Marker saved",
    ));

    expect(sent, isTrue);
  });
}
