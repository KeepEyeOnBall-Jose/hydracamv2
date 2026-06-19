import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("hydracamv2/fixed_camera_hls_test");

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test("getCapabilities maps the native fixed-camera HLS response", () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "getCapabilities");
      return {
        "platform": "android",
        "channelAvailable": true,
        "nativeRecorderImplemented": true,
        "cameraRecorderImplemented": true,
        "recorderMode": "synthetic_local",
        "supportedRecorderModes": ["synthetic_local", "camera2_hls"],
        "cameraIds": ["back-0"],
        "requiresCameraHardware": false,
        "supportsHlsUpload": true,
        "supportedMimeTypes": [
          "application/vnd.apple.mpegurl",
          "video/mp4",
          "video/iso.segment",
        ],
        "outputDirectoryPath": "/storage/emulated/0/Android/data/hls",
        "androidSdk": 35,
        "reason": "Synthetic local HLS is the default; pass cameraId to use "
            "Camera2 HLS recording.",
      };
    });

    final service = FixedCameraHlsRecorderService(channel: channel);

    final capabilities = await service.getCapabilities();

    expect(capabilities.platform, "android");
    expect(capabilities.channelAvailable, isTrue);
    expect(capabilities.nativeRecorderImplemented, isTrue);
    expect(capabilities.cameraRecorderImplemented, isTrue);
    expect(capabilities.recorderMode, "synthetic_local");
    expect(capabilities.supportedRecorderModes,
        ["synthetic_local", "camera2_hls"]);
    expect(capabilities.cameraIds, ["back-0"]);
    expect(capabilities.requiresCameraHardware, isFalse);
    expect(capabilities.supportsHlsUpload, isTrue);
    expect(capabilities.canRecordNativeHls, isTrue);
    expect(capabilities.canRecordCameraHls, isTrue);
    expect(capabilities.androidSdk, 35);
    expect(capabilities.supportedMimeTypes, [
      "application/vnd.apple.mpegurl",
      "video/mp4",
      "video/iso.segment",
    ]);
    expect(
      capabilities.outputDirectoryPath,
      "/storage/emulated/0/Android/data/hls",
    );
    expect(
      capabilities.reason,
      "Synthetic local HLS is the default; pass cameraId to use "
      "Camera2 HLS recording.",
    );
  });

  test("getCapabilities reports unsupported when the native channel is missing",
      () async {
    final service = FixedCameraHlsRecorderService(channel: channel);

    final capabilities = await service.getCapabilities();

    expect(capabilities.platform, "unknown");
    expect(capabilities.channelAvailable, isFalse);
    expect(capabilities.nativeRecorderImplemented, isFalse);
    expect(capabilities.cameraRecorderImplemented, isFalse);
    expect(capabilities.recorderMode, isNull);
    expect(capabilities.supportedRecorderModes, isEmpty);
    expect(capabilities.cameraIds, isEmpty);
    expect(capabilities.requiresCameraHardware, isTrue);
    expect(capabilities.supportsHlsUpload, isTrue);
    expect(capabilities.canRecordNativeHls, isFalse);
    expect(capabilities.canRecordCameraHls, isFalse);
    expect(capabilities.supportedMimeTypes, isEmpty);
    expect(capabilities.outputDirectoryPath, isNull);
    expect(capabilities.reason, contains("not available"));
  });

  test("startRecording sends fixed-camera HLS request to native channel",
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "startRecording");
      expect(call.arguments, {
        "sessionGuid": "session-123",
        "deviceId": "fixed-court-a",
        "recordingId": "game-1-camera-a",
        "cameraId": "0",
        "targetDurationSeconds": 2,
        "width": 1920,
        "height": 1080,
        "frameRate": 30,
        "includeAudio": true,
      });
      return {
        "recordingId": "game-1-camera-a",
        "recordingDirectoryPath": "/tmp/hls/game-1-camera-a",
        "startedAt": "2026-06-19T11:00:00.000Z",
        "state": "recording",
      };
    });

    final service = FixedCameraHlsRecorderService(channel: channel);

    final result = await service.startRecording(
      const FixedCameraHlsRecordingRequest(
        sessionGuid: "session-123",
        deviceId: "fixed-court-a",
        recordingId: "game-1-camera-a",
        cameraId: "0",
        targetDurationSeconds: 2,
        width: 1920,
        height: 1080,
        frameRate: 30,
        includeAudio: true,
      ),
    );

    expect(result.recordingId, "game-1-camera-a");
    expect(result.recordingDirectoryPath, "/tmp/hls/game-1-camera-a");
    expect(result.state, FixedCameraHlsRecordingState.recording);
    expect(result.startedAt, DateTime.parse("2026-06-19T11:00:00.000Z"));
  });

  test("stopRecording returns finalized HLS bundle paths from native channel",
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, "stopRecording");
      expect(call.arguments, {"recordingId": "game-1-camera-a"});
      return {
        "recordingId": "game-1-camera-a",
        "recordingDirectoryPath": "/tmp/hls/game-1-camera-a",
        "playlistPath": "/tmp/hls/game-1-camera-a/playlist.m3u8",
        "initPath": "/tmp/hls/game-1-camera-a/init.mp4",
        "chunkPaths": [
          "/tmp/hls/game-1-camera-a/chunk-00000000.m4s",
          "/tmp/hls/game-1-camera-a/chunk-00000001.m4s",
        ],
        "durationSeconds": 4.02,
        "targetDurationSeconds": 2,
        "startedAt": "2026-06-19T11:00:00.000Z",
        "finalizedAt": "2026-06-19T11:00:04.020Z",
        "nativeTimingMetadataJson": "{\"syncConfidence\":\"yellow\"}",
        "state": "finalized",
      };
    });

    final service = FixedCameraHlsRecorderService(channel: channel);

    final result = await service.stopRecording("game-1-camera-a");

    expect(result.recordingId, "game-1-camera-a");
    expect(result.recordingDirectoryPath, "/tmp/hls/game-1-camera-a");
    expect(result.playlistPath, "/tmp/hls/game-1-camera-a/playlist.m3u8");
    expect(result.initPath, "/tmp/hls/game-1-camera-a/init.mp4");
    expect(result.chunkPaths, [
      "/tmp/hls/game-1-camera-a/chunk-00000000.m4s",
      "/tmp/hls/game-1-camera-a/chunk-00000001.m4s",
    ]);
    expect(result.durationSeconds, 4.02);
    expect(result.targetDurationSeconds, 2);
    expect(result.state, FixedCameraHlsRecordingState.finalized);
    expect(result.nativeTimingMetadataJson, "{\"syncConfidence\":\"yellow\"}");
  });

  test("toHlsStreamBundle parses finalized native recording output", () async {
    final tempDir = Directory.systemTemp.createTempSync(
      "hydracam_fixed_camera_result_bundle_test",
    );
    try {
      File("${tempDir.path}/playlist.m3u8").writeAsStringSync("""
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXT-X-MAP:URI="init.mp4"
#EXTINF:2.0,
fixed-court-a-game-1-camera-a-00000000.m4s
#EXT-X-ENDLIST
""");
      File("${tempDir.path}/init.mp4").writeAsBytesSync([0, 0, 0, 1]);
      File("${tempDir.path}/fixed-court-a-game-1-camera-a-00000000.m4s")
          .writeAsBytesSync([1, 2, 3]);
      final result = FixedCameraHlsRecordingResult(
        recordingId: "game-1-camera-a",
        recordingDirectoryPath: tempDir.path,
        state: FixedCameraHlsRecordingState.finalized,
        playlistPath: "${tempDir.path}/playlist.m3u8",
        initPath: "${tempDir.path}/init.mp4",
        chunkPaths: [
          "${tempDir.path}/fixed-court-a-game-1-camera-a-00000000.m4s",
        ],
      );

      final bundle = await result.toHlsStreamBundle();

      expect(bundle.playlist.path, result.playlistPath);
      expect(bundle.initSegment?.path, result.initPath);
      expect(
        bundle.chunks.map((chunk) => chunk.path).toList(),
        result.chunkPaths,
      );
      expect(bundle.targetDuration, const Duration(seconds: 2));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
