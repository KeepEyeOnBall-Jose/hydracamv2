import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

import "package:hydracam/services/fixed_camera_hls_recorder_service.dart";
import "package:hydracam/services/local_hls_server.dart";

/// Throwaway foreground entrypoint that proves in-app HLS playback on the
/// device: it locates a finalized fixed-camera HLS bundle in the app's output
/// directory, serves it through [LocalHlsServer], and plays it with
/// `video_player` (Android ExoPlayer). The decoded player state is printed for
/// host capture. Launch with
/// `flutter run -t tool/hls_player_proof_main.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _App());
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  String _status = "starting";
  VideoPlayerController? _controller;
  LocalHlsServer? _server;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 2), _run);
    });
  }

  Future<void> _run() async {
    try {
      final caps = await FixedCameraHlsRecorderService().getCapabilities();
      final root = caps.outputDirectoryPath;
      _log("HLS_PLAYER_PROOF_ROOT $root");
      if (root == null) {
        _log("HLS_PLAYER_PROOF_FAIL no output directory");
        return;
      }
      final bundleDir = _findBundle(Directory(root));
      if (bundleDir == null) {
        _log("HLS_PLAYER_PROOF_FAIL no bundle with playlist.m3u8 under $root");
        setState(() => _status = "no bundle");
        return;
      }
      _log("HLS_PLAYER_PROOF_BUNDLE ${bundleDir.path}");

      final server = LocalHlsServer(bundleDirectory: bundleDir);
      _server = server;
      final url = await server.start();
      _log("HLS_PLAYER_PROOF_URL $url");

      final controller = VideoPlayerController.networkUrl(url);
      _controller = controller;
      await controller.initialize();
      await controller.play();
      await Future<void>.delayed(const Duration(seconds: 2));

      final v = controller.value;
      _log("HLS_PLAYER_PROOF_STATE initialized=${v.isInitialized} "
          "size=${v.size.width}x${v.size.height} "
          "duration=${v.duration.inMilliseconds}ms "
          "position=${v.position.inMilliseconds}ms "
          "isPlaying=${v.isPlaying} hasError=${v.hasError} "
          "error=${v.errorDescription}");
      if (v.isInitialized &&
          v.size.width > 0 &&
          v.duration.inMilliseconds > 0 &&
          !v.hasError) {
        _log("HLS_PLAYER_PROOF_OK");
        setState(() => _status = "playing ${v.size.width.toInt()}x"
            "${v.size.height.toInt()}");
      } else {
        _log("HLS_PLAYER_PROOF_FAIL player not healthy");
        setState(() => _status = "unhealthy");
      }
    } catch (error, stack) {
      _log("HLS_PLAYER_PROOF_ERROR $error\n$stack");
      setState(() => _status = "error: $error");
    }
  }

  /// Returns the newest immediate subdirectory that contains a playlist.m3u8.
  Directory? _findBundle(Directory root) {
    if (!root.existsSync()) {
      return null;
    }
    final candidates = root
        .listSync()
        .whereType<Directory>()
        .where((dir) => File("${dir.path}/playlist.m3u8").existsSync())
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return candidates.isEmpty ? null : candidates.first;
  }

  void _log(String line) {
    // ignore: avoid_print
    print(line);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: controller != null && controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                )
              : Text("HLS player proof: $_status",
                  style: const TextStyle(color: Colors.white, fontSize: 20)),
        ),
      ),
    );
  }
}
