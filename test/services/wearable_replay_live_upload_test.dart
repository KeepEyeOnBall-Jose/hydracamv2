import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/models/wearable_replay.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/services/wearable_replay_service.dart";
import "package:hydracam/services/wearable_replay_upload_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const liveUploadEnabled =
      bool.fromEnvironment("HYDRACAM_WEARABLE_LIVE_UPLOAD");
  const apiBaseUrl = String.fromEnvironment(
    "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL",
    defaultValue: "http://127.0.0.1:3001/api",
  );

  late Directory documentsDirectory;
  late _TestPathProviderPlatform pathProvider;
  late SessionManager sessionManager;

  setUp(() async {
    documentsDirectory =
        Directory.systemTemp.createTempSync("wearable_replay_live_upload");
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

  test(
    "uploads a HydraCam-generated wearable manifest to media-timeline",
    () async {
      final sessionGuid =
          "wearable-live-${DateTime.now().microsecondsSinceEpoch}";
      const participantId = "player-live-1";
      const pairedHydraCamDeviceId = "phone-live-1";
      const watchTrackId = "watch-live-track";
      const povTrackId = "rayban-live-track";
      const recordingId = "rayban-live-pov";
      final startedAt = DateTime.utc(2026, 6, 22, 12);
      final sync = SyncMetadata(
        offsetMs: 9,
        minRoundTripMs: 6,
        uncertaintyMs: 11,
        confidence: TimeSyncConfidence.green,
        sampleCount: 8,
        calibratedAt: startedAt.subtract(const Duration(seconds: 4)),
        calibrationAgeMs: 4000,
      );
      final watchContext = WearableRecordContext.fromLocalTimestamp(
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: "galaxy-watch4-live-sim",
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        localTimestamp: startedAt.add(const Duration(seconds: 1)),
        syncMetadata: sync,
      );
      final raybanContext = WearableRecordContext.fromLocalTimestamp(
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: "rayban-meta-live-sim",
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        localTimestamp: startedAt.add(const Duration(seconds: 2)),
        syncMetadata: sync,
      );

      sessionManager.startSession(
        sessionGuid,
        "wearable-live-session-id",
        deviceType: "Master",
      );

      final replayService = WearableReplayService(
        documentsDirectoryProvider: () async => documentsDirectory,
        now: () => DateTime.utc(2026, 6, 22, 12, 0, 10),
        maxSamplesPerChunk: 2,
      );
      await replayService.recordTrack(WearableTrack(
        trackId: watchTrackId,
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: "galaxy-watch4-live-sim",
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        sourceKind: WearableSourceKind.galaxyWatch,
        trackKind: WearableTrackKind.telemetry,
        displayName: "Galaxy Watch4 live upload simulation",
        startedAt: startedAt,
        syncMetadata: sync,
      ));
      await replayService.recordTrack(WearableTrack(
        trackId: povTrackId,
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: "rayban-meta-live-sim",
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        sourceKind: WearableSourceKind.rayBanMeta,
        trackKind: WearableTrackKind.pov,
        displayName: "Ray-Ban Meta live upload simulation",
        startedAt: startedAt,
        syncMetadata: sync,
        metadata: const {
          "fallbackReason": "meta_dat_unavailable_simulated_rolling_buffer",
        },
      ));
      for (var index = 0; index < 3; index += 1) {
        await replayService.appendSample(WearableSample(
          sampleId: "sample-live-$index",
          trackId: watchTrackId,
          context: WearableRecordContext.fromLocalTimestamp(
            sessionGuid: sessionGuid,
            participantId: participantId,
            sourceDeviceId: "galaxy-watch4-live-sim",
            pairedHydraCamDeviceId: pairedHydraCamDeviceId,
            localTimestamp: startedAt.add(Duration(seconds: index)),
            syncMetadata: sync,
          ),
          heartRateBpm: 146 + index,
          accelerometerX: 0.1 * index,
          accelerometerY: 0.2 * index,
          accelerometerZ: 9.7,
          gyroscopeX: 0.3 * index,
          gyroscopeY: 0.4 * index,
          gyroscopeZ: 0.5 * index,
          motionIntensity: 0.76,
        ));
      }
      await replayService.recordMarker(WearableMarker(
        markerId: "marker-live-1",
        trackId: watchTrackId,
        context: watchContext,
        markerType: "player_marker",
        label: "Live upload proof marker",
      ));
      await replayService.recordSyncCalibration(WearableSyncCalibration(
        calibrationId: "clap-flash-live-1",
        context: WearableRecordContext.fromLocalTimestamp(
          sessionGuid: sessionGuid,
          participantId: participantId,
          sourceDeviceId: pairedHydraCamDeviceId,
          pairedHydraCamDeviceId: pairedHydraCamDeviceId,
          localTimestamp: startedAt.add(const Duration(seconds: 3)),
          syncMetadata: sync,
        ),
        ritual: "clap_flash",
        observedSourceDeviceIds: const [
          "galaxy-watch4-live-sim",
          "rayban-meta-live-sim",
          pairedHydraCamDeviceId,
        ],
        targetAlignmentMs: 50,
        measuredAlignmentErrorMs: 27,
        performedAt: startedAt.add(const Duration(seconds: 3)),
        metadata: const {"proofMode": "live_media_timeline_simulation"},
      ));

      final povSource = File("${documentsDirectory.path}/$recordingId.mp4")
        ..writeAsBytesSync(List<int>.generate(64, (index) => index % 255));
      await replayService.recordPovRecording(PovRecording(
        recordingId: recordingId,
        trackId: povTrackId,
        context: raybanContext,
        mediaPath: povSource.path,
        captureMode: PovCaptureMode.rollingHighlight,
        startedAt: startedAt.add(const Duration(seconds: 2)),
        endedAt: startedAt.add(const Duration(seconds: 10)),
        hasAudio: true,
      ));
      await replayService.recordFeedbackEvent(FeedbackEvent(
        feedbackId: "feedback-live-watch-1",
        trackId: watchTrackId,
        context: watchContext,
        channel: FeedbackChannel.watchHaptic,
        trigger: "marker_saved",
        message: "Marker saved",
      ));
      await replayService.recordFeedbackEvent(FeedbackEvent(
        feedbackId: "feedback-live-glasses-1",
        trackId: povTrackId,
        context: raybanContext,
        channel: FeedbackChannel.glassesAudio,
        trigger: "capture_state_confirmed",
        message: "Capture ready",
      ));

      final manifestFile = await replayService.writeUploadManifest(sessionGuid);
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(manifest["trackFiles"], hasLength(2));
      expect(manifest["sampleFiles"], hasLength(2));
      expect(manifest["calibrationFiles"], hasLength(1));
      expect(manifest["povMediaFiles"], hasLength(1));
      expect(manifest["feedbackFiles"], hasLength(2));

      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() {
        HttpOverrides.global = previousHttpOverrides;
      });
      final client = http.Client();
      addTearDown(client.close);
      final uploadService = WearableReplayUploadService(
        baseApiUrl: apiBaseUrl,
        httpClient: client,
      );
      final uploadResult = await uploadService.uploadManifest(
        sessionGuid: sessionGuid,
        manifestFile: manifestFile,
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        participantId: participantId,
      );

      expect(uploadResult.sessionGuid, sessionGuid);
      expect(uploadResult.trackCount, 2);
      expect(uploadResult.sampleFileCount, 2);
      expect(uploadResult.calibrationCount, 1);
      expect(uploadResult.markerCount, 1);
      expect(uploadResult.povRecordingCount, 1);
      expect(uploadResult.povMediaCount, 1);
      expect(uploadResult.feedbackCount, 2);

      final enrichedResponse = await client.get(_apiUri(
        apiBaseUrl,
        ["events", uploadResult.eventId, "media", "enriched"],
      ));
      expect(enrichedResponse.statusCode, 200);
      final enriched = jsonDecode(enrichedResponse.body) as List<dynamic>;
      final povRow = enriched.cast<Map<String, dynamic>>().singleWhere(
            (row) => row["wearableReplay"] is Map,
          );
      final replay = povRow["wearableReplay"] as Map<String, dynamic>;
      expect(replay["replayAngle"], isTrue);
      expect(replay["participantId"], participantId);
      expect(replay["sourceDeviceId"], "rayban-meta-live-sim");
      expect(replay["captureMode"], "rollingHighlight");
      expect(replay["hasAudio"], isTrue);
      expect(replay["audioPublishDefault"], isTrue);
      expect(replay["reviewRequired"], isTrue);
      expect(replay["syncConfidence"], "green");
      expect((replay["overlays"] as Map<String, dynamic>)["heartRate"], isTrue);
      expect((replay["overlays"] as Map<String, dynamic>)["motion"], isTrue);
      expect((replay["overlays"] as Map<String, dynamic>)["markers"], isTrue);
      expect((replay["sidecars"] as Map<String, dynamic>)["sampleCount"], 3);
      expect(
        (replay["sidecars"] as Map<String, dynamic>)["calibrationCount"],
        1,
      );
      expect((replay["sidecars"] as Map<String, dynamic>)["feedbackCount"], 2);
    },
    skip: liveUploadEnabled
        ? false
        : "Set HYDRACAM_WEARABLE_LIVE_UPLOAD=true and "
            "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL to run the live upload proof.",
  );
}

Uri _apiUri(String apiBaseUrl, List<String> pathSegments) {
  final baseUri = Uri.parse(apiBaseUrl);
  final baseSegments = baseUri.pathSegments
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  return baseUri.replace(pathSegments: [...baseSegments, ...pathSegments]);
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
