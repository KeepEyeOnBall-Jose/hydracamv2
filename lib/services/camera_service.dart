import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  Function(String)? onPhotoTaken; // Callback to notify SlaveScreen

  // Constructor to include the callback
  CameraService({this.onPhotoTaken});

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

  Future<String> takePhoto() async {
    try {
      final XFile photo = await _controller!.takePicture();
      print("Photo taken at path: ${photo.path}");

      if (onPhotoTaken != null) {
        onPhotoTaken!(photo.path);
      }

      return photo.path;
    } catch (e) {
      print("Error taking photo: $e");
      return "Error taking photo";
    }
  }

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
