import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";
import "package:integration_test/integration_test.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("Android fixed-camera channel writes a local HLS bundle",
      (tester) async {
    final service = FixedCameraHlsRecorderService();
    final capabilities = await service.getCapabilities();

    expect(capabilities.platform, "android");
    expect(capabilities.recorderMode, "synthetic_local");
    expect(capabilities.canRecordNativeHls, isTrue);
    expect(capabilities.supportedRecorderModes, contains("synthetic_local"));
    expect(capabilities.supportedRecorderModes, contains("camera2_hls"));
    expect(capabilities.requiresCameraHardware, isFalse);

    final recordingId = "integration-game-1-"
        "${DateTime.now().millisecondsSinceEpoch}";
    final started = await service.startRecording(
      FixedCameraHlsRecordingRequest(
        sessionGuid: "integration-session",
        deviceId: "fixed-court-a",
        recordingId: recordingId,
        targetDurationSeconds: 1,
        width: 640,
        height: 360,
        frameRate: 30,
        includeAudio: true,
      ),
    );

    expect(started.state, FixedCameraHlsRecordingState.recording);
    expect(started.recordingId, recordingId);

    final finalized = await service.stopRecording(recordingId);

    expect(finalized.state, FixedCameraHlsRecordingState.finalized);
    expect(finalized.recordingId, recordingId);
    expect(finalized.durationSeconds, greaterThanOrEqualTo(0));
    expect(finalized.targetDurationSeconds, 1);
    expect(finalized.playlistPath, isNotNull);
    expect(finalized.initPath, isNotNull);
    expect(finalized.chunkPaths, hasLength(2));

    final playlistPath = finalized.playlistPath!;
    final initPath = finalized.initPath!;
    expect(File(playlistPath).existsSync(), isTrue);
    expect(File(initPath).existsSync(), isTrue);
    for (final chunkPath in finalized.chunkPaths) {
      expect(File(chunkPath).existsSync(), isTrue);
    }

    final playlist = File(playlistPath).readAsStringSync();
    expect(playlist, contains("#EXT-X-MAP:URI=\"init.mp4\""));
    expect(playlist, contains("#EXT-X-ENDLIST"));
    expect(
      finalized.nativeTimingMetadataJson,
      contains("\"recorderMode\":\"synthetic_local\""),
    );
  });

  testWidgets("Android fixed-camera channel writes a Camera2 HLS bundle",
      (tester) async {
    final service = FixedCameraHlsRecorderService();
    final capabilities = await service.getCapabilities();
    if (!capabilities.canRecordCameraHls) {
      return;
    }
    if (capabilities.cameraIds.isEmpty) {
      return;
    }
    final cameraId = capabilities.cameraIds.first;

    final recordingId = "integration-camera2-game-1-"
        "${DateTime.now().millisecondsSinceEpoch}";
    final started = await service.startRecording(
      FixedCameraHlsRecordingRequest(
        sessionGuid: "integration-session-camera2",
        deviceId: "fixed-court-a",
        recordingId: recordingId,
        cameraId: cameraId,
        targetDurationSeconds: 1,
        width: 640,
        height: 480,
        frameRate: 30,
        includeAudio: false,
      ),
    );

    expect(started.state, FixedCameraHlsRecordingState.recording);
    await tester.pump(const Duration(seconds: 2));

    final finalized = await service.stopRecording(recordingId);

    expect(finalized.state, FixedCameraHlsRecordingState.finalized);
    expect(finalized.recordingId, recordingId);
    expect(finalized.playlistPath, isNotNull);
    expect(finalized.initPath, isNotNull);
    expect(finalized.chunkPaths, isNotEmpty);
    expect(File(finalized.playlistPath!).existsSync(), isTrue);
    expect(File(finalized.initPath!).existsSync(), isTrue);
    for (final chunkPath in finalized.chunkPaths) {
      expect(File(chunkPath).existsSync(), isTrue);
    }
    expect(
      finalized.nativeTimingMetadataJson,
      contains("\"recorderMode\":\"camera2_hls\""),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
