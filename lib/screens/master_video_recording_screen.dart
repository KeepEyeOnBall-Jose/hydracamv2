import "dart:async";

import "package:flutter/material.dart";
import "../models/captured_video.dart";
import "../services/camera_service.dart";
import "../services/log_service.dart";
import "../services/settings_service.dart";
import "../widgets/camera_preview_widget.dart";
import "../widgets/animated_countdown_timer.dart";

class MasterVideoRecordingScreen extends StatefulWidget {
  final CameraService cameraService;
  final Future<CapturedVideo> Function() onStopRecording;

  const MasterVideoRecordingScreen({
    super.key,
    required this.cameraService,
    required this.onStopRecording,
  });

  @override
  MasterVideoRecordingScreenState createState() =>
      MasterVideoRecordingScreenState();
}

class MasterVideoRecordingScreenState
    extends State<MasterVideoRecordingScreen> {
  bool _isStopping = false; // State variable to avoid button spam

  Future<void> _handleStopRecording() async {
    if (_isStopping) return; // Prevent multiple presses

    // Get possible timer
    final timerDuration = await SettingsService.getTimerDuration();

    if (timerDuration > 0) {
      // Get scheduled time
      final DateTime scheduledTime =
          DateTime.now().add(Duration(seconds: timerDuration));

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AnimatedCountdownTimer(
            duration: scheduledTime.difference(DateTime.now()).inMilliseconds,
            onComplete: () => Navigator.of(context).pop(),
          ),
        );
      }

      // Wait for timer to stop
      await Future.delayed(scheduledTime.difference(DateTime.now()));

      if (!mounted) return;
    }

    setState(() {
      _isStopping = true;
    });

    if (!mounted) return;

    final navigator = Navigator.of(context);

    try {
      final capturedVideo = await widget.onStopRecording();
      if (mounted) {
        navigator.pop(capturedVideo);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error stopping recording: $error")),
        );

        setState(() {
          _isStopping = false;
        });
      }
    }
  }

  bool get _recordingActive {
    return widget.cameraService.isRecording ||
        (widget.cameraService.controller?.value.isRecordingVideo ?? false);
  }

  void _handleExitPreview() {
    if (_isStopping) return;

    if (_recordingActive) {
      unawaited(_handleStopRecording());
      return;
    }

    LogService.instance.registerLog(
        "Closing recording preview because no recording is active.");
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();

    // Listen to interruption from CameraService
    widget.cameraService.recordingInterrupted.addListener(() {
      if (widget.cameraService.recordingInterrupted.value) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    widget.cameraService.recordingInterrupted.removeListener(() {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.cameraService.controller;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleExitPreview();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // Absorb taps
          child: Stack(
            children: [
              // Full-screen camera preview
              Positioned.fill(
                child: controller == null
                    ? const SizedBox.expand()
                    : CameraPreviewWidget(controller: controller),
              ),
              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  tooltip: "Exit recording preview",
                  onPressed: _isStopping ? null : _handleExitPreview,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              // Stop Recording button
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: _isStopping
                        ? null
                        : () => unawaited(
                              _handleStopRecording(),
                            ), // Disable if stopping
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text("Stop Recording"),
                  ),
                ),
              ),
              // Loading indicator
              if (_isStopping)
                Positioned.fill(
                  child: Container(
                    color: Colors.black
                        .withValues(alpha: 0.5), // Semi-transparent overlay
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            "Processing video, please wait...",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
