import 'package:camera/camera.dart';

/// CameraService - Manages camera operations on slave devices.
class CameraService {
  CameraController? _controller;

  /// Starts the camera and prepares for recording or capturing images.
  Future<void> startCamera() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      await _controller?.startVideoRecording();
      print("Camera started recording");
    } catch (e) {
      print("Error starting camera: $e");
    }
  }

  /// Stops the camera recording and releases resources.
  Future<void> stopCamera() async {
    try {
      await _controller?.stopVideoRecording();
      await _controller?.dispose();
      print("Camera stopped recording");
    } catch (e) {
      print("Error stopping camera: $e");
    }
  }
}
