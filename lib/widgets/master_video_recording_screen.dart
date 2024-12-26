import 'package:flutter/material.dart';
import '../models/CapturedVideo.dart';
import '../services/camera_service.dart';
import '../services/settings_service.dart';
import '../widgets/camera_preview_widget.dart';
import 'animated_countdown_timer.dart';

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

  bool _isStopping = false; // State variable to avoid button spam

  void _handleStopRecording() async{

    if (_isStopping) return; // Prevent multiple presses

    // Get possible timer
    final timerDuration = await SettingsService.getTimerDuration();

    if (timerDuration > 0){
      // Get scheduled time
      final DateTime scheduledTime = DateTime.now().add(Duration(seconds: timerDuration));

      if(context.mounted){
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
    }

    setState(() {
      _isStopping = true;
    });


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

        setState(() {
          _isStopping = false;
        });

      }
    });
  }

  @override
  void initState() {
    super.initState();

    // Listen to interruption from CameraService
    widget.cameraService.recordingInterrupted.addListener(() {
      // Print statement to log the change in the notifier value
      print("ValueNotifier update received. Current value: ${widget.cameraService.recordingInterrupted.value}");

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
    return WillPopScope(
      onWillPop: () async => false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // Absorb taps
          child: Stack(
            children: [
              // Full-screen camera preview
              Positioned.fill(
                child: CameraPreviewWidget(controller: widget.cameraService.controller!),
              ),
              // Stop Recording button
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: _isStopping ? null : _handleStopRecording, // Disable if stopping
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text('Stop Recording'),
                  ),
                ),
              ),
              // Loading indicator
              if (_isStopping)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.5), // Semi-transparent overlay
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Processing video, please wait...',
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
