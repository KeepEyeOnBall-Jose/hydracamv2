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

  /// Takes a real photo and returns the file path.
  Future<String> takePhoto() async {
    try {
      final XFile photo = await _controller!.takePicture();
      print("Photo taken at path: ${photo.path}");
      return photo.path;
    } catch (e) {
      print("Error taking photo: $e");
      return "Error taking photo";
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
