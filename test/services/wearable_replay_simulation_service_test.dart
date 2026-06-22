import "dart:convert";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/services/wearable_replay_bridge_service.dart";
import "package:hydracam/services/wearable_replay_service.dart";
import "package:hydracam/services/wearable_replay_simulation_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("hydracamv2/wearable_replay_simulation_test");
  late Directory documentsDirectory;
  late Directory nativeDirectory;
  late _TestPathProviderPlatform pathProvider;
  late SessionManager sessionManager;

  setUp(() async {
    documentsDirectory = Directory.systemTemp.createTempSync(
      "wearable_replay_simulation_docs",
    );
    nativeDirectory = Directory.systemTemp.createTempSync(
      "wearable_replay_native_mock",
    );
    pathProvider = _TestPathProviderPlatform(documentsDirectory.path);
    PathProviderPlatform.instance = pathProvider;
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    sessionManager = SessionManager.instance;
    UploaderService().reset();
    if (sessionManager.isSessionActive) {
      await sessionManager.endSession();
    }
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (sessionManager.isSessionActive) {
      await sessionManager.endSession();
    }
    pathProvider.dispose();
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
    if (nativeDirectory.existsSync()) {
      nativeDirectory.deleteSync(recursive: true);
    }
  });

  test("runs a mock private-match wearable replay proof bundle", () async {
    const sessionGuid = "wearable-simulation-session";
    var pollCount = 0;
    final feedbackCalls = <Map<dynamic, dynamic>>[];
    final povMediaPath = "${nativeDirectory.path}/pov-player-1-1.mp4";

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case "getCapabilities":
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
        case "pollWatchTelemetry":
          pollCount += 1;
          return {
            "sourceDeviceId": "galaxy-watch4-sim",
            "localTimestamp": DateTime.utc(
              2026,
              6,
              22,
              12,
              0,
              pollCount,
            ).toIso8601String(),
            "heartRateBpm": 140 + pollCount,
            "interBeatIntervalMs": 420 - pollCount,
            "accelerometerX": 0.1 * pollCount,
            "accelerometerY": 0.2 * pollCount,
            "accelerometerZ": 9.6,
            "gyroscopeX": 0.3 * pollCount,
            "gyroscopeY": 0.4 * pollCount,
            "gyroscopeZ": 0.5 * pollCount,
            "motionIntensity": 0.8,
            "mockReading": true,
          };
        case "startMetaPovCapture":
          expect(
              call.arguments, containsPair("captureMode", "rollingHighlight"));
          expect(call.arguments, containsPair("targetDurationSeconds", 12));
          File(povMediaPath).writeAsBytesSync([0, 1, 2, 3]);
          return {
            "recordingId": "pov-player-1-1",
            "mediaPath": povMediaPath,
            "startedAt": "2026-06-22T12:00:00.000Z",
            "endedAt": "2026-06-22T12:00:00.000Z",
            "captureMode": "rollingHighlight",
            "hasAudio": true,
            "mockCapture": true,
          };
        case "stopMetaPovCapture":
          return {
            "recordingId": "pov-player-1-1",
            "mediaPath": povMediaPath,
            "startedAt": "2026-06-22T12:00:00.000Z",
            "endedAt": "2026-06-22T12:00:08.000Z",
            "captureMode": "rollingHighlight",
            "hasAudio": true,
            "mockCapture": true,
          };
        case "sendFeedback":
          feedbackCalls.add(call.arguments as Map<dynamic, dynamic>);
          return true;
      }
      fail("Unexpected method ${call.method}");
    });

    sessionManager.startSession(
      sessionGuid,
      "wearable-simulation-id",
      deviceType: "Master",
    );
    final replayService = WearableReplayService(
      documentsDirectoryProvider: () async => documentsDirectory,
      now: () => DateTime.utc(2026, 6, 22, 12, 0, 10),
      maxSamplesPerChunk: 2,
    );
    final simulationService = WearableReplaySimulationService(
      bridgeService: WearableReplayBridgeService(channel: channel),
      replayService: replayService,
      sessionManager: sessionManager,
      now: () => DateTime.utc(2026, 6, 22, 12),
    );

    final result = await simulationService.runPrivateMatchProof(
      participantId: "player-1",
      pairedHydraCamDeviceId: "phone-1",
      sampleCount: 3,
    );

    final manifestFile = File(result.manifestPath);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

    expect(result.capabilities.canSimulateWearableReplay, isTrue);
    expect(result.sampleCount, 3);
    expect(result.markerCount, 1);
    expect(result.calibrationCount, 1);
    expect(result.maxAlignmentErrorMs, lessThanOrEqualTo(50));
    expect(result.alignmentWithinTarget, isTrue);
    expect(result.povRecordingCount, 1);
    expect(result.feedbackCount, 2);
    expect(result.feedbackSentCount, 2);
    expect(result.feedbackSent, isTrue);
    expect(pollCount, 3);
    expect(feedbackCalls, hasLength(2));
    expect(
      feedbackCalls.map((call) => call["channel"]),
      ["watchHaptic", "glassesAudio"],
    );
    expect(manifest["sessionGuid"], sessionGuid);
    expect(manifest["trackFiles"], hasLength(3));
    expect(manifest["sampleFiles"], hasLength(2));
    expect(manifest["calibrationFiles"], hasLength(1));
    expect(manifest["markerFiles"], hasLength(1));
    expect(manifest["povRecordingFiles"], hasLength(1));
    final povMediaFiles = manifest["povMediaFiles"] as List<dynamic>;
    expect(povMediaFiles, hasLength(1));
    expect(povMediaFiles.single,
        endsWith("/wearables/pov-media/pov-player-1-1.mp4"));
    final povSidecar = File(
      "${documentsDirectory.path}/session_$sessionGuid/wearables/pov/"
      "pov-player-1-1.json",
    );
    final povJson =
        jsonDecode(povSidecar.readAsStringSync()) as Map<String, dynamic>;
    expect(povJson["captureMode"], "rollingHighlight");
    expect(povJson["metadata"], {
      "mockCapture": true,
      "requestedCaptureMode": "rollingHighlight",
      "fallbackReason": "meta_dat_unavailable_simulated_rolling_buffer",
    });
    expect(manifest["feedbackFiles"], hasLength(2));
    final calibrationSidecar = File(
      "${documentsDirectory.path}/session_$sessionGuid/wearables/calibration/"
      "clap-flash-player-1-1.json",
    );
    final calibrationJson = jsonDecode(calibrationSidecar.readAsStringSync())
        as Map<String, dynamic>;
    expect(calibrationJson["recordType"], "wearableSyncCalibration");
    expect(calibrationJson["ritual"], "clap_flash");
    expect(calibrationJson["targetAlignmentMs"], 50);
    expect(calibrationJson["measuredAlignmentErrorMs"], lessThanOrEqualTo(50));
    expect(calibrationJson["withinTarget"], isTrue);
    expect(File(povMediaPath).existsSync(), isTrue);
    expect(File(povMediaFiles.single as String).existsSync(), isTrue);
    expect(
      (manifest["mediaTimelineIntent"]
          as Map<String, dynamic>)["registerPovAsReplayAngle"],
      isTrue,
    );
    expect(
      (manifest["mediaTimelineIntent"]
          as Map<String, dynamic>)["requirePrePublishReview"],
      isTrue,
    );
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.documentsPath);

  final String documentsPath;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (_disposed) {
      return null;
    }
    return documentsPath;
  }
}
