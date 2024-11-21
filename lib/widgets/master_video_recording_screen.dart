import 'package:flutter/material.dart';
import '../models/CapturedVideo.dart';
import '../services/camera_service.dart';
import '../widgets/camera_preview_widget.dart';

class MasterVideoRecordingScreen extends StatefulWidget {
  final CameraService cameraService;
  final Future<CapturedVideo> Function() onStopRecording;

  const MasterVideoRecordingScreen({
    Key? key,
    required this.cameraService,
    required this.onStopRecording,
  }) : super(key: key);

  @override
  _MasterVideoRecordingScreenState createState() => _MasterVideoRecordingScreenState();
}

class _MasterVideoRecordingScreenState extends State<MasterVideoRecordingScreen> {
  void _handleStopRecording() {
    final navigator = Navigator.of(context);

    widget.onStopRecording().then((capturedVideo) {
      if (mounted) {
        navigator.pop(capturedVideo);
      }
    }).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $error')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: Colors.black, // Ensure the background is opaque
        appBar: null,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque, // Capture all touch events
          onTap: () {}, // Empty handler to absorb taps
          child: Stack(
            children: [
              // Full-screen camera preview
              Positioned.fill(
                child: CameraPreviewWidget(controller: widget.cameraService.controller!),
              ),
              // Stop Recording button at the bottom center
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: _handleStopRecording,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: TextStyle(fontSize: 18),
                    ),
                    child: Text('Stop Recording'),
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
