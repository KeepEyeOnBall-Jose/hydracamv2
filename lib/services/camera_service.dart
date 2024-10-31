import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  Function(String)? onPhotoTaken; // Callback to notify SlaveScreen about photos
  Function(String)? onVideoRecorded; // Callback to notify SlaveScreen about videos

  // Constructor to include the callbacks
  CameraService({this.onPhotoTaken, this.onVideoRecorded});

  Future<void> startCamera() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      print("Camera initialized");
    } catch (e) {
      print("Error initializing camera: $e");
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

  Future<void> startRecordingVideo() async {
    try {
      await _controller?.startVideoRecording();
      print("Video recording started");
    } catch (e) {
      print("Error starting video recording: $e");
    }
  }

  Future<String> stopRecordingVideo() async {
    try {
      final XFile video = await _controller!.stopVideoRecording();
      print("Video recorded at path: ${video.path}");

      if (onVideoRecorded != null) {
        onVideoRecorded!(video.path);
      }

      return video.path;
    } catch (e) {
      print("Error stopping video recording: $e");
      return "Error stopping video recording";
    }
  }

  Future<void> stopCamera() async {
    try {
      await _controller?.dispose();
      print("Camera stopped");
    } catch (e) {
      print("Error stopping camera: $e");
    }
  }
}
