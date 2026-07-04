import "dart:convert";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";
import "package:integration_test/integration_test.dart";

/// Hardware evidence test for the real Camera2 HLS recorder path.
///
/// Unlike the smoke test in `fixed_camera_hls_channel_test.dart`, this:
///  1. Fails loudly if no camera is available (so a missing camera cannot be
///     silently mistaken for a pass on hardware).
///  2. Concatenates the finalized `init.mp4` + `.m4s` fragments into one fMP4
///     and inspects it through the platform `MediaMetadataRetriever`, proving
///     Android's own media stack decodes the encoded camera output.
///  3. Emits every bundle file as base64 between sentinels so the host harness
///     can reconstruct the bundle and validate it with ffprobe, surviving the
///     app uninstall that `flutter test` performs at the end of the run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const videoMetadataChannel = MethodChannel("hydracamv2/video_metadata");

  testWidgets(
    "Camera2 HLS recorder produces a decodable bundle on hardware",
    (tester) async {
      final service = FixedCameraHlsRecorderService();
      final capabilities = await service.getCapabilities();

      expect(capabilities.platform, "android");
      expect(
        capabilities.cameraIds,
        isNotEmpty,
        reason: "No camera hardware detected; cannot prove Camera2 HLS.",
      );
      expect(capabilities.canRecordCameraHls, isTrue);

      final cameraId = capabilities.cameraIds.first;
      final recordingId =
          "camera2-evidence-${DateTime.now().millisecondsSinceEpoch}";

      // `flutter test` reinstalls the app clean, which can drop the runtime
      // camera/mic grants. A host-side loop re-grants them; retry start until
      // the platform side stops reporting a permission error.
      FixedCameraHlsRecordingResult? started;
      Object? lastError;
      for (var attempt = 0; attempt < 30; attempt++) {
        try {
          started = await service.startRecording(
            FixedCameraHlsRecordingRequest(
              sessionGuid: "camera2-evidence-session",
              deviceId: "fixed-court-a",
              recordingId: recordingId,
              cameraId: cameraId,
              targetDurationSeconds: 2,
              width: 640,
              height: 480,
              frameRate: 30,
              includeAudio: false,
            ),
          );
          break;
        } catch (error) {
          lastError = error;
          await tester.pump(const Duration(milliseconds: 700));
        }
      }
      expect(
        started,
        isNotNull,
        reason: "startRecording never succeeded; last error: $lastError",
      );
      expect(started!.state, FixedCameraHlsRecordingState.recording);

      // Let the real camera produce frames before stopping.
      await tester.pump(const Duration(seconds: 4));

      final finalized = await service.stopRecording(recordingId);
      expect(finalized.state, FixedCameraHlsRecordingState.finalized);
      expect(finalized.playlistPath, isNotNull);
      expect(finalized.initPath, isNotNull);
      expect(finalized.chunkPaths, isNotEmpty);
      expect(
        finalized.nativeTimingMetadataJson,
        contains("\"recorderMode\":\"camera2_hls\""),
      );

      final playlistFile = File(finalized.playlistPath!);
      final initFile = File(finalized.initPath!);
      final chunkFiles =
          finalized.chunkPaths.map((path) => File(path)).toList();

      expect(playlistFile.existsSync(), isTrue);
      expect(initFile.existsSync(), isTrue);
      for (final chunk in chunkFiles) {
        expect(chunk.existsSync(), isTrue);
      }

      // Build a single fMP4 (init + fragments) and confirm Android decodes it.
      final concat = File("${initFile.parent.path}/camera2-concat.mp4");
      final sink = concat.openWrite();
      sink.add(await initFile.readAsBytes());
      for (final chunk in chunkFiles) {
        sink.add(await chunk.readAsBytes());
      }
      await sink.close();

      final metadata = await videoMetadataChannel
          .invokeMethod<Map<dynamic, dynamic>>(
        "inspectVideo",
        {"path": concat.path},
      );
      expect(metadata, isNotNull);
      final width = metadata!["width"];
      final height = metadata["height"];
      final durationMs = metadata["durationMs"];
      expect(width, 640, reason: "Decoded width should match capture width.");
      expect(height, 480, reason: "Decoded height should match capture height.");
      expect(
        durationMs is int && durationMs > 0,
        isTrue,
        reason: "Decoded duration must be positive: $durationMs",
      );

      // Emit the full bundle as base64 for host-side ffprobe reconstruction.
      final bundleFiles = <String, File>{
        "playlist.m3u8": playlistFile,
        "init.mp4": initFile,
        for (final chunk in chunkFiles)
          chunk.uri.pathSegments.last: chunk,
      };
      _emit("CAMERA2_EVIDENCE_BEGIN recordingId=$recordingId "
          "width=$width height=$height durationMs=$durationMs "
          "chunks=${chunkFiles.length}");
      bundleFiles.forEach((name, file) {
        final b64 = base64Encode(file.readAsBytesSync());
        _emit("CAMERA2_FILE_BEGIN name=$name bytes=${file.lengthSync()}");
        for (var i = 0; i < b64.length; i += 480) {
          _emit("CAMERA2_B64 ${b64.substring(i, (i + 480).clamp(0, b64.length))}");
        }
        _emit("CAMERA2_FILE_END name=$name");
      });
      _emit("CAMERA2_EVIDENCE_END recordingId=$recordingId");
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

void _emit(String line) {
  // ignore: avoid_print
  print(line);
}
