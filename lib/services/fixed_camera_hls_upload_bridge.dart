import "fixed_camera_hls_recorder_service.dart";
import "hls_stream_upload_queue.dart";
import "hls_stream_upload_service.dart";

extension FixedCameraHlsUploadBridge on HlsStreamUploadQueue {
  Future<HlsStreamUploadQueueEntry> addFinalizedRecording({
    required String sessionGuid,
    required FixedCameraHlsRecordingResult recording,
    required String deviceId,
    DateTime? capturedAt,
  }) async {
    final nativeTimingMetadataJson = recording.nativeTimingMetadataJson;
    return addBundle(
      sessionGuid: sessionGuid,
      bundle: await recording.toHlsStreamBundle(),
      deviceId: deviceId,
      capturedAt: capturedAt ??
          recording.startedAt ??
          recording.finalizedAt ??
          DateTime.now().toUtc(),
      recordingId: recording.recordingId,
      timingMetadata: nativeTimingMetadataJson == null
          ? null
          : HlsStreamTimingMetadata.rawJson(nativeTimingMetadataJson),
    );
  }
}
