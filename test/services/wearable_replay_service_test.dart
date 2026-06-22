import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/models/wearable_replay.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/services/wearable_replay_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDirectory;
  late _TestPathProviderPlatform pathProvider;
  late SessionManager sessionManager;

  setUp(() async {
    documentsDirectory =
        Directory.systemTemp.createTempSync("wearable_replay_service_docs");
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
    if (sessionManager.isSessionActive) {
      await sessionManager.endSession();
    }
    pathProvider.dispose();
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
  });

  test("rejects wearable data when no HydraCam session is active", () async {
    final service = WearableReplayService(
      documentsDirectoryProvider: () async => documentsDirectory,
    );

    expect(
      service.appendSample(_sample("missing-session", 1)),
      throwsStateError,
    );
  });

  test("writes bounded telemetry chunks and replay sidecars", () async {
    const sessionGuid = "wearable-session";
    sessionManager.startSession(
      sessionGuid,
      "wearable-session-id",
      deviceType: "Master",
    );
    final service = WearableReplayService(
      documentsDirectoryProvider: () async => documentsDirectory,
      now: () => DateTime.utc(2026, 6, 22, 12),
      maxSamplesPerChunk: 2,
    );
    final sync = _sync();
    final context = WearableRecordContext.fromLocalTimestamp(
      sessionGuid: sessionGuid,
      participantId: "player-1",
      sourceDeviceId: "watch-1",
      pairedHydraCamDeviceId: "phone-1",
      localTimestamp: DateTime.utc(2026, 6, 22, 11),
      syncMetadata: sync,
    );

    await service.recordTrack(WearableTrack(
      trackId: "watch-track",
      sessionGuid: sessionGuid,
      participantId: "player-1",
      sourceDeviceId: "watch-1",
      pairedHydraCamDeviceId: "phone-1",
      sourceKind: WearableSourceKind.galaxyWatch,
      trackKind: WearableTrackKind.telemetry,
      displayName: "Galaxy Watch4 telemetry",
      startedAt: DateTime.utc(2026, 6, 22, 11),
      syncMetadata: sync,
    ));
    await service.appendSample(_sample(sessionGuid, 1));
    await service.appendSample(_sample(sessionGuid, 2));
    await service.appendSample(_sample(sessionGuid, 3));
    await service.recordMarker(WearableMarker(
      markerId: "marker-1",
      trackId: "watch-track",
      context: context,
      markerType: "player_marker",
      label: "Great rally",
    ));
    await service.recordSyncCalibration(WearableSyncCalibration(
      calibrationId: "clap-flash-1",
      context: context,
      ritual: "clap_flash",
      observedSourceDeviceIds: const [
        "watch-1",
        "rayban-meta-1",
        "phone-1",
      ],
      targetAlignmentMs: 50,
      measuredAlignmentErrorMs: 24,
      performedAt: DateTime.utc(2026, 6, 22, 11),
      metadata: const {"proofMode": "simulated"},
    ));
    File("${documentsDirectory.path}/pov-1.mp4").writeAsBytesSync([1, 2, 3]);
    await service.recordPovRecording(PovRecording(
      recordingId: "pov-1",
      trackId: "pov-track",
      context: context,
      mediaPath: "${documentsDirectory.path}/pov-1.mp4",
      captureMode: PovCaptureMode.rollingHighlight,
      startedAt: DateTime.utc(2026, 6, 22, 11),
      endedAt: DateTime.utc(2026, 6, 22, 11, 0, 8),
      hasAudio: true,
    ));
    await service.recordFeedbackEvent(FeedbackEvent(
      feedbackId: "feedback-1",
      trackId: "watch-track",
      context: context,
      channel: FeedbackChannel.watchHaptic,
      trigger: "marker_saved",
      message: "Marker saved",
    ));

    final manifestFile = await service.writeUploadManifest(sessionGuid);
    final sessionDir = Directory(
      "${documentsDirectory.path}/session_$sessionGuid/wearables",
    );
    final chunk0 =
        File("${sessionDir.path}/samples/watch-track-chunk-0000.jsonl");
    final chunk1 =
        File("${sessionDir.path}/samples/watch-track-chunk-0001.jsonl");
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

    expect(chunk0.readAsLinesSync(), hasLength(2));
    expect(chunk1.readAsLinesSync(), hasLength(1));
    expect(
        File("${sessionDir.path}/markers/marker-1.json").existsSync(), isTrue);
    expect(
      File("${sessionDir.path}/calibration/clap-flash-1.json").existsSync(),
      isTrue,
    );
    expect(File("${sessionDir.path}/pov/pov-1.json").existsSync(), isTrue);
    expect(
      File("${sessionDir.path}/feedback/feedback-1.json").existsSync(),
      isTrue,
    );
    expect(manifest["manifestVersion"], 1);
    expect(manifest["sessionGuid"], sessionGuid);
    expect(manifest["sampleFiles"], hasLength(2));
    expect(manifest["calibrationFiles"], hasLength(1));
    expect(
      manifest["povMediaFiles"],
      ["${sessionDir.path}/pov-media/pov-1.mp4"],
    );
    expect(
      (manifest["mediaTimelineIntent"]
          as Map<String, dynamic>)["renderHeartRateOverlay"],
      isTrue,
    );
    expect(
      (manifest["mediaTimelineIntent"]
          as Map<String, dynamic>)["requirePrePublishReview"],
      isTrue,
    );
  });
}

WearableSample _sample(String sessionGuid, int index) {
  final sync = _sync();
  return WearableSample(
    sampleId: "sample-$index",
    trackId: "watch-track",
    context: WearableRecordContext.fromLocalTimestamp(
      sessionGuid: sessionGuid,
      participantId: "player-1",
      sourceDeviceId: "watch-1",
      pairedHydraCamDeviceId: "phone-1",
      localTimestamp: DateTime.utc(2026, 6, 22, 11, 0, index),
      syncMetadata: sync,
    ),
    heartRateBpm: 140 + index,
    accelerometerX: 0.1 * index,
    accelerometerY: 0.2 * index,
    accelerometerZ: 9.6,
    gyroscopeX: 0.3 * index,
    gyroscopeY: 0.4 * index,
    gyroscopeZ: 0.5 * index,
    motionIntensity: 0.7,
  );
}

SyncMetadata _sync() {
  return SyncMetadata(
    offsetMs: 12,
    minRoundTripMs: 7,
    uncertaintyMs: 10,
    confidence: TimeSyncConfidence.green,
    sampleCount: 8,
    calibratedAt: DateTime.utc(2026, 6, 22, 10, 59),
    calibrationAgeMs: 1000,
  );
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
