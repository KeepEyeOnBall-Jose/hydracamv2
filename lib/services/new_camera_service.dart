import '../constants.dart';

abstract class NewCameraService {
  /// Initializes the camera service.
  Future<void> initializeCameras();

  /// Starts the camera.
  Future<void> startCamera();

  /// Stops the camera and disposes of its resources.
  Future<void> stopCamera();

  /// Captures a photo and saves it.
  Future<String> takePhoto({bool enableFlash = false});

  /// Starts recording a video.
  Future<void> startRecordingVideo({bool enableFlash = false});

  /// Stops recording a video and saves it.
  Future<String> stopRecordingVideo();

  /// Sets the camera quality and reinitializes the controller.
  Future<void> setCameraQuality(CameraQuality quality);

  /// Returns the current camera quality.
  CameraQuality get currentQuality;

  /// Returns a list of available cameras.
  List<dynamic> getAvailableCameras();

  /// Selects a camera by index.
  Future<void> selectCamera(int index);

  /// Getter for accessing the controller (platform-specific).
  dynamic get controller;
}
