import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";

/// Throwaway foreground entrypoint used to prove the real Camera2 HLS recorder
/// on hardware. `flutter test` integration mode runs an instrumentation
/// activity that Samsung's CameraService treats as not-active, so the camera
/// never opens there. Launched as a normal app via
/// `flutter run -t tool/camera2_hls_proof_main.dart`, the activity is resumed
/// and active, so Camera2 opens. The recorded bundle is validated through the
/// platform `MediaMetadataRetriever` and emitted as base64 for host capture.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProofApp());
}

class _ProofApp extends StatefulWidget {
  const _ProofApp();

  @override
  State<_ProofApp> createState() => _ProofAppState();
}

class _ProofAppState extends State<_ProofApp> {
  static const _videoMetadata = MethodChannel("hydracamv2/video_metadata");
  String _status = "starting";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Give the activity a beat to fully resume so the camera UID is active.
      Future<void>.delayed(const Duration(seconds: 2), _runProof);
    });
  }

  Future<void> _runProof() async {
    final service = FixedCameraHlsRecorderService();
    try {
      final capabilities = await service.getCapabilities();
      _log("CAMERA2_PROOF_CAPS platform=${capabilities.platform} "
          "cameraIds=${capabilities.cameraIds.join("|")} "
          "cameraRecorder=${capabilities.canRecordCameraHls}");
      if (capabilities.cameraIds.isEmpty) {
        _log("CAMERA2_PROOF_FAIL no camera ids");
        setState(() => _status = "no cameras");
        return;
      }
      final cameraId = capabilities.cameraIds.first;
      final mode = capabilities.highestModeForCamera(cameraId);
      final width = mode?.width ?? 1920;
      final height = mode?.height ?? 1080;
      final frameRate = (mode?.maxFps ?? 30).clamp(1, 30);
      _log("CAMERA2_PROOF_MODE ${mode?.label ?? "default 1920x1080"} "
          "(${capabilities.cameraModes.length} modes advertised)");
      final recordingId =
          "camera2-run-proof-${DateTime.now().millisecondsSinceEpoch}";

      FixedCameraHlsRecordingResult? started;
      Object? lastError;
      for (var attempt = 0; attempt < 75; attempt++) {
        try {
          started = await service.startRecording(
            FixedCameraHlsRecordingRequest(
              sessionGuid: "camera2-run-proof",
              deviceId: "fixed-court-a",
              recordingId: recordingId,
              cameraId: cameraId,
              targetDurationSeconds: 4,
              width: width,
              height: height,
              frameRate: frameRate,
              includeAudio: true,
            ),
          );
          break;
        } catch (error) {
          lastError = error;
          _log("CAMERA2_PROOF_RETRY attempt=$attempt error=$error");
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
      if (started == null) {
        _log("CAMERA2_PROOF_FAIL startRecording never succeeded: $lastError");
        setState(() => _status = "start failed");
        return;
      }
      _log("CAMERA2_PROOF_STARTED ${started.recordingId}");
      setState(() => _status = "recording");

      await Future<void>.delayed(const Duration(seconds: 4));
      final finalized = await service.stopRecording(recordingId);
      _log("CAMERA2_PROOF_FINALIZED state=${finalized.state} "
          "chunks=${finalized.chunkPaths.length} "
          "duration=${finalized.durationSeconds}");

      final initFile = File(finalized.initPath!);
      final chunkFiles = finalized.chunkPaths.map(File.new).toList();
      final playlistFile = File(finalized.playlistPath!);

      // Concatenate init + fragments and confirm the platform decodes it.
      final concat = File("${initFile.parent.path}/camera2-concat.mp4");
      final sink = concat.openWrite();
      sink.add(await initFile.readAsBytes());
      for (final chunk in chunkFiles) {
        sink.add(await chunk.readAsBytes());
      }
      await sink.close();
      final metadata = await _videoMetadata.invokeMethod<Map<dynamic, dynamic>>(
        "inspectVideo",
        {"path": concat.path},
      );
      _log("CAMERA2_PROOF_DECODE width=${metadata?["width"]} "
          "height=${metadata?["height"]} durationMs=${metadata?["durationMs"]}");

      final bundleFiles = <String, File>{
        "playlist.m3u8": playlistFile,
        "init.mp4": initFile,
        for (final chunk in chunkFiles) chunk.uri.pathSegments.last: chunk,
      };
      _log("CAMERA2_PROOF_BEGIN recordingId=$recordingId "
          "timing=${finalized.nativeTimingMetadataJson}");
      bundleFiles.forEach((name, file) {
        final b64 = base64Encode(file.readAsBytesSync());
        _log("CAMERA2_FILE_BEGIN name=$name bytes=${file.lengthSync()}");
        for (var i = 0; i < b64.length; i += 480) {
          _log("CAMERA2_B64 "
              "${b64.substring(i, (i + 480).clamp(0, b64.length))}");
        }
        _log("CAMERA2_FILE_END name=$name");
      });
      _log("CAMERA2_PROOF_END recordingId=$recordingId");
      setState(() => _status = "done");
    } catch (error, stack) {
      _log("CAMERA2_PROOF_ERROR $error\n$stack");
      setState(() => _status = "error: $error");
    }
  }

  void _log(String line) {
    // ignore: avoid_print
    print(line);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "Camera2 HLS proof: $_status",
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
