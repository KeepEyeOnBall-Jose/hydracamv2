import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/hls_stream_bundle.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";
import "package:hydracam/services/fixed_camera_hls_upload_bridge.dart";
import "package:hydracam/services/hls_stream_upload_queue.dart";
import "package:hydracam/services/hls_stream_upload_service.dart";

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("hydracam_hls_queue_test");
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("startUploadingManually retries a finalized HLS bundle upload",
      () async {
    final bundle = await _createBundle(tempDir);
    var attempts = 0;
    final queue = HlsStreamUploadQueue(
      maxAttempts: 3,
      retryDelay: Duration.zero,
      sleep: (_) async {},
      uploadBundle: ({
        required sessionGuid,
        required bundle,
        required deviceId,
        required capturedAt,
        recordingId,
        timingMetadata,
      }) async {
        attempts += 1;
        expect(sessionGuid, "session-queue-retry");
        expect(deviceId, "fixed-court-a");
        expect(recordingId, "game-1-camera-a");
        if (attempts == 1) {
          throw const SocketException("temporary network loss");
        }
        return const HlsStreamUploadResult(
          eventId: "event-queue-retry",
          sessionGuid: "session-queue-retry",
          fileId: "playlist-file-1",
          filename: "playlist.m3u8",
        );
      },
    );

    final entry = queue.addBundle(
      sessionGuid: "session-queue-retry",
      bundle: bundle,
      deviceId: "fixed-court-a",
      capturedAt: DateTime.utc(2026, 6, 19, 12),
      recordingId: "game-1-camera-a",
    );

    await queue.startUploadingManually();

    expect(attempts, 2);
    expect(entry.status, HlsStreamUploadQueueStatus.uploaded);
    expect(entry.attempts, 2);
    expect(entry.result?.fileId, "playlist-file-1");
    expect(entry.lastError, isNull);
    expect(queue.queueLength, 0);
    expect(queue.isUploading, isFalse);
  });

  test("startUploadingManually marks HLS bundle failed after max attempts",
      () async {
    final bundle = await _createBundle(tempDir);
    var attempts = 0;
    final queue = HlsStreamUploadQueue(
      maxAttempts: 2,
      retryDelay: Duration.zero,
      sleep: (_) async {},
      uploadBundle: ({
        required sessionGuid,
        required bundle,
        required deviceId,
        required capturedAt,
        recordingId,
        timingMetadata,
      }) async {
        attempts += 1;
        throw const SocketException("media-timeline unavailable");
      },
    );

    final entry = queue.addBundle(
      sessionGuid: "session-queue-failure",
      bundle: bundle,
      deviceId: "fixed-court-a",
      capturedAt: DateTime.utc(2026, 6, 19, 12),
      recordingId: "game-1-camera-a",
    );

    await queue.startUploadingManually();

    expect(attempts, 2);
    expect(entry.status, HlsStreamUploadQueueStatus.failed);
    expect(entry.attempts, 2);
    expect(entry.result, isNull);
    expect(entry.lastError, contains("media-timeline unavailable"));
    expect(queue.queueLength, 0);
    expect(queue.isUploading, isFalse);
  });

  test("addFinalizedRecording enqueues native HLS output for upload", () async {
    final bundle = await _createBundle(tempDir);
    const rawTimingMetadata =
        "{\"recorderMode\":\"synthetic_local\",\"chunkCount\":1}";
    final recording = FixedCameraHlsRecordingResult(
      recordingId: "game-1-camera-a",
      recordingDirectoryPath: tempDir.path,
      state: FixedCameraHlsRecordingState.finalized,
      playlistPath: bundle.playlist.path,
      initPath: bundle.initSegment?.path,
      chunkPaths: bundle.chunks.map((chunk) => chunk.path).toList(),
      startedAt: DateTime.parse("2026-06-19T12:00:00.000Z"),
      finalizedAt: DateTime.parse("2026-06-19T12:00:04.000Z"),
      nativeTimingMetadataJson: rawTimingMetadata,
    );
    var uploads = 0;
    final queue = HlsStreamUploadQueue(
      retryDelay: Duration.zero,
      sleep: (_) async {},
      uploadBundle: ({
        required sessionGuid,
        required bundle,
        required deviceId,
        required capturedAt,
        recordingId,
        timingMetadata,
      }) async {
        uploads += 1;
        expect(sessionGuid, "session-native-recording");
        expect(deviceId, "fixed-court-a");
        expect(recordingId, "game-1-camera-a");
        expect(capturedAt, DateTime.parse("2026-06-19T12:00:00.000Z"));
        expect(bundle.playlist.path, recording.playlistPath);
        expect(bundle.initSegment?.path, recording.initPath);
        expect(
          bundle.chunks.map((chunk) => chunk.path).toList(),
          recording.chunkPaths,
        );
        expect(timingMetadata?.toWireJsonString(), rawTimingMetadata);
        return const HlsStreamUploadResult(
          eventId: "event-native-recording",
          sessionGuid: "session-native-recording",
          fileId: "playlist-native-recording",
          filename: "playlist.m3u8",
        );
      },
    );

    final entry = await queue.addFinalizedRecording(
      sessionGuid: "session-native-recording",
      recording: recording,
      deviceId: "fixed-court-a",
    );

    await queue.startUploadingManually();

    expect(uploads, 1);
    expect(entry.status, HlsStreamUploadQueueStatus.uploaded);
    expect(entry.result?.fileId, "playlist-native-recording");
  });
}

Future<HlsStreamBundle> _createBundle(Directory directory) async {
  File("${directory.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
squash-court-a-00000000.m4s
""");
  File("${directory.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
  File("${directory.path}/squash-court-a-00000000.m4s")
      .writeAsBytesSync([1, 2, 3]);
  return HlsStreamBundle.fromDirectory(directory);
}
