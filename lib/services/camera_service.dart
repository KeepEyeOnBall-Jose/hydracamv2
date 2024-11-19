import 'package:camera/camera.dart';
import 'package:gallery_saver/gallery_saver.dart';

class CameraService {
  CameraController? _controller;
  bool _isCameraInitialized = false; // Tracks camera initialization status

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

  /// Ensures the camera is ready before any operation
  Future<void> ensureCameraIsReady() async {
    if (_isCameraInitialized && _controller?.value.isInitialized == true) {
      print("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    print("Initializing camera...");
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      _isCameraInitialized = true;
      print("Camera successfully initialized.");
    } catch (e) {
      print("Error initializing camera: $e");
      _isCameraInitialized = false;
      throw Exception("Failed to initialize camera: $e");
    }
  }

  Future<String> takePhoto() async {
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before taking a photo

      final XFile photo = await _controller!.takePicture();
      print("Photo taken at path: ${photo.path}");

      // Save to gallery
      await GallerySaver.saveImage(photo.path, albumName: 'HydraCam');

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
      await ensureCameraIsReady(); // Ensure the camera is ready before taking a photo

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

      // Save to gallery
      await GallerySaver.saveVideo(video.path, albumName: 'HydraCam');

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
