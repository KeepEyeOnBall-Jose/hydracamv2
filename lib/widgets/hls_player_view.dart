import "dart:io";

import "package:flutter/material.dart";
import "package:video_player/video_player.dart";

import "../app_theme.dart";
import "../services/local_hls_server.dart";

/// Plays a finalized local HLS bundle in-app by serving it over a loopback
/// HTTP server and handing the playlist URL to [VideoPlayerController].
///
/// On Android `video_player` uses ExoPlayer, which natively understands HLS
/// (`.m3u8` + fMP4 `init.mp4`/`.m4s`). This gives HydraCam on-device replay of
/// a recording without uploading it first.
class HlsPlayerView extends StatefulWidget {
  const HlsPlayerView({
    super.key,
    required this.bundleDirectory,
    this.playlistName = "playlist.m3u8",
    this.autoPlay = true,
    this.serverFactory,
  });

  final Directory bundleDirectory;
  final String playlistName;
  final bool autoPlay;

  /// Injectable for tests so the widget can be exercised without a platform
  /// video plugin. Defaults to a real [LocalHlsServer].
  final LocalHlsServer Function(Directory directory, String playlistName)?
      serverFactory;

  @override
  State<HlsPlayerView> createState() => _HlsPlayerViewState();
}

class _HlsPlayerViewState extends State<HlsPlayerView> {
  LocalHlsServer? _server;
  VideoPlayerController? _controller;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final server = (widget.serverFactory ?? _defaultServerFactory)(
      widget.bundleDirectory,
      widget.playlistName,
    );
    _server = server;
    try {
      final url = await server.start();
      final controller = VideoPlayerController.networkUrl(url);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        return;
      }
      setState(() => _ready = true);
      if (widget.autoPlay) {
        await controller.play();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    }
  }

  static LocalHlsServer _defaultServerFactory(
    Directory directory,
    String playlistName,
  ) =>
      LocalHlsServer(bundleDirectory: directory, playlistName: playlistName);

  @override
  void dispose() {
    _controller?.dispose();
    // Fire-and-forget; the server closes its sockets on the next event loop.
    _server?.stop();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          "HLS playback failed: $error",
          key: const Key("hlsPlayerError"),
          style: const TextStyle(color: AppTheme.danger),
        ),
      );
    }

    final controller = _controller;
    if (!_ready || controller == null) {
      return const Center(
        key: Key("hlsPlayerLoading"),
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        IconButton(
          key: const Key("hlsPlayerToggle"),
          icon: Icon(
            controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
          onPressed: _togglePlayback,
        ),
      ],
    );
  }
}
