import "../models/sync_metadata.dart";
import "../models/wearable_replay.dart";
import "session_manager.dart";
import "wearable_replay_bridge_service.dart";
import "wearable_replay_service.dart";

class WearableReplaySimulationResult {
  const WearableReplaySimulationResult({
    required this.capabilities,
    required this.sampleCount,
    required this.markerCount,
    required this.calibrationCount,
    required this.maxAlignmentErrorMs,
    required this.alignmentWithinTarget,
    required this.povRecordingCount,
    required this.feedbackCount,
    required this.feedbackSentCount,
    required this.feedbackSent,
    required this.manifestPath,
  });

  final WearableReplayBridgeCapabilities capabilities;
  final int sampleCount;
  final int markerCount;
  final int calibrationCount;
  final int maxAlignmentErrorMs;
  final bool alignmentWithinTarget;
  final int povRecordingCount;
  final int feedbackCount;
  final int feedbackSentCount;
  final bool feedbackSent;
  final String manifestPath;
}

class WearableReplaySimulationService {
  WearableReplaySimulationService({
    WearableReplayBridgeService? bridgeService,
    WearableReplayService? replayService,
    SessionManager? sessionManager,
    DateTime Function()? now,
  })  : _bridgeService = bridgeService ?? WearableReplayBridgeService(),
        _replayService = replayService ?? WearableReplayService(),
        _sessionManager = sessionManager ?? SessionManager.instance,
        _now = now ?? DateTime.now;

  final WearableReplayBridgeService _bridgeService;
  final WearableReplayService _replayService;
  final SessionManager _sessionManager;
  final DateTime Function() _now;

  Future<WearableReplaySimulationResult> runPrivateMatchProof({
    required String participantId,
    required String pairedHydraCamDeviceId,
    String watchDeviceId = "galaxy-watch4-sim",
    String glassesDeviceId = "rayban-meta-sim",
    int sampleCount = 5,
  }) async {
    final sessionGuid = _sessionManager.sessionGuid?.trim();
    if (!_sessionManager.isSessionActive ||
        sessionGuid == null ||
        sessionGuid.isEmpty) {
      throw StateError("No active HydraCam session for wearable replay proof.");
    }

    final capabilities = await _bridgeService.getCapabilities();
    if (!capabilities.canSimulateWearableReplay) {
      throw StateError(
        "Wearable replay simulation requires Meta and watch mock support.",
      );
    }
    if (!capabilities.metaDatAvailable &&
        !capabilities.supportsRollingPovFallback) {
      throw StateError(
        "Wearable replay simulation requires rolling POV fallback when "
        "Meta DAT is unavailable.",
      );
    }

    final sync = SyncMetadata.masterAnchor(at: _now());
    final startedAt = _now();
    final povCaptureMode = capabilities.metaDatAvailable
        ? PovCaptureMode.continuous
        : PovCaptureMode.rollingHighlight;
    final povFallbackReason = capabilities.metaDatAvailable
        ? null
        : "meta_dat_unavailable_simulated_rolling_buffer";
    await _replayService.recordTrack(WearableTrack(
      trackId: "watch-$participantId",
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: watchDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      sourceKind: WearableSourceKind.galaxyWatch,
      trackKind: WearableTrackKind.telemetry,
      displayName: "Galaxy Watch4 telemetry",
      startedAt: startedAt,
      syncMetadata: sync,
      metadata: const {
        "proofMode": "simulated",
        "preferredApi": "wear_os_health_services",
      },
    ));
    await _replayService.recordTrack(WearableTrack(
      trackId: "pov-$participantId",
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: glassesDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      sourceKind: WearableSourceKind.rayBanMeta,
      trackKind: WearableTrackKind.pov,
      displayName: "Ray-Ban Meta POV",
      startedAt: startedAt,
      syncMetadata: sync,
      metadata: {
        "proofMode": "simulated",
        "preferredApi": "meta_wearables_dat",
        "requestedCaptureMode": povCaptureMode.name,
        if (povFallbackReason != null) "fallbackReason": povFallbackReason,
      },
    ));
    await _replayService.recordTrack(WearableTrack(
      trackId: "feedback-$participantId",
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: pairedHydraCamDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      sourceKind: WearableSourceKind.phone,
      trackKind: WearableTrackKind.feedback,
      displayName: "Between-point feedback cues",
      startedAt: startedAt,
      syncMetadata: sync,
      metadata: const {"proofMode": "simulated"},
    ));

    for (var index = 0; index < sampleCount; index += 1) {
      final reading = await _bridgeService.pollWatchTelemetry(
        sourceDeviceId: watchDeviceId,
      );
      await _replayService.appendSample(WearableSample(
        sampleId: "watch-$participantId-$index",
        trackId: "watch-$participantId",
        context: WearableRecordContext.fromLocalTimestamp(
          sessionGuid: sessionGuid,
          participantId: participantId,
          sourceDeviceId: reading.sourceDeviceId,
          pairedHydraCamDeviceId: pairedHydraCamDeviceId,
          localTimestamp: reading.localTimestamp,
          syncMetadata: sync,
        ),
        heartRateBpm: reading.heartRateBpm,
        interBeatIntervalMs: reading.interBeatIntervalMs,
        accelerometerX: reading.accelerometerX,
        accelerometerY: reading.accelerometerY,
        accelerometerZ: reading.accelerometerZ,
        gyroscopeX: reading.gyroscopeX,
        gyroscopeY: reading.gyroscopeY,
        gyroscopeZ: reading.gyroscopeZ,
        motionIntensity: reading.motionIntensity,
        metadata: {"mockReading": reading.mockReading},
      ));
    }

    final markerContext = WearableRecordContext.fromLocalTimestamp(
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: watchDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      localTimestamp: _now(),
      syncMetadata: sync,
    );
    await _replayService.recordMarker(WearableMarker(
      markerId: "marker-$participantId-1",
      trackId: "watch-$participantId",
      context: markerContext,
      markerType: "player_marker",
      label: "Player highlight marker",
      metadata: const {"proofMode": "simulated"},
    ));
    final calibration = WearableSyncCalibration(
      calibrationId: "clap-flash-$participantId-1",
      context: WearableRecordContext.fromLocalTimestamp(
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: pairedHydraCamDeviceId,
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        localTimestamp: _now(),
        syncMetadata: sync,
      ),
      ritual: "clap_flash",
      observedSourceDeviceIds: [
        pairedHydraCamDeviceId,
        watchDeviceId,
        glassesDeviceId,
      ],
      targetAlignmentMs: 50,
      measuredAlignmentErrorMs: 27,
      performedAt: _now(),
      metadata: const {
        "proofMode": "simulated",
        "method": "synthetic_clap_flash_fixture",
      },
    );
    await _replayService.recordSyncCalibration(calibration);

    final captureRequest = MetaPovCaptureRequest(
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: glassesDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      recordingId: "pov-$participantId-1",
      captureMode: povCaptureMode,
      includeAudio: true,
      targetDurationSeconds:
          povCaptureMode == PovCaptureMode.continuous ? 30 : 12,
    );
    await _bridgeService.startMetaPovCapture(captureRequest);
    final povResult = await _bridgeService.stopMetaPovCapture(
      captureRequest.recordingId,
    );
    await _replayService.recordPovRecording(PovRecording(
      recordingId: povResult.recordingId,
      trackId: "pov-$participantId",
      context: WearableRecordContext.fromLocalTimestamp(
        sessionGuid: sessionGuid,
        participantId: participantId,
        sourceDeviceId: glassesDeviceId,
        pairedHydraCamDeviceId: pairedHydraCamDeviceId,
        localTimestamp: povResult.startedAt,
        syncMetadata: sync,
      ),
      mediaPath: povResult.mediaPath,
      captureMode: povResult.captureMode,
      startedAt: povResult.startedAt,
      endedAt: povResult.endedAt,
      hasAudio: povResult.hasAudio,
      metadata: {
        "mockCapture": povResult.mockCapture,
        "requestedCaptureMode": povCaptureMode.name,
        if (povFallbackReason != null) "fallbackReason": povFallbackReason,
      },
    ));

    final feedbackEvents = [
      FeedbackEvent(
        feedbackId: "feedback-$participantId-watch-1",
        trackId: "feedback-$participantId",
        context: markerContext,
        channel: FeedbackChannel.watchHaptic,
        trigger: "marker_saved",
        message: "Marker saved",
        metadata: const {"proofMode": "simulated"},
      ),
      FeedbackEvent(
        feedbackId: "feedback-$participantId-glasses-1",
        trackId: "feedback-$participantId",
        context: WearableRecordContext.fromLocalTimestamp(
          sessionGuid: sessionGuid,
          participantId: participantId,
          sourceDeviceId: glassesDeviceId,
          pairedHydraCamDeviceId: pairedHydraCamDeviceId,
          localTimestamp: _now(),
          syncMetadata: sync,
        ),
        channel: FeedbackChannel.glassesAudio,
        trigger: "capture_state_confirmed",
        message: "Capture ready",
        metadata: const {"proofMode": "simulated"},
      ),
    ];
    var feedbackSentCount = 0;
    for (final feedback in feedbackEvents) {
      final sent = await _bridgeService.sendFeedback(feedback);
      if (sent) {
        feedbackSentCount += 1;
      }
      await _replayService.recordFeedbackEvent(feedback);
    }

    final manifest = await _replayService.writeUploadManifest(sessionGuid);
    return WearableReplaySimulationResult(
      capabilities: capabilities,
      sampleCount: sampleCount,
      markerCount: 1,
      calibrationCount: 1,
      maxAlignmentErrorMs: calibration.measuredAlignmentErrorMs,
      alignmentWithinTarget: calibration.withinTarget,
      povRecordingCount: 1,
      feedbackCount: feedbackEvents.length,
      feedbackSentCount: feedbackSentCount,
      feedbackSent: feedbackSentCount == feedbackEvents.length,
      manifestPath: manifest.path,
    );
  }
}
