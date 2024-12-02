import 'package:camera/camera.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:hydracam/services/settings_service.dart';
import '../constants.dart';
import 'log_service.dart';
import 'new_camera_service.dart';

/// MobileCameraService - Manages camera operations for mobile platforms using the `camera` plugin.
class MobileCameraService implements NewCameraService {
  CameraController? _controller; // The camera controller instance
  @override
  CameraController? get controller => _controller;

  bool _isCameraInitialized = false; // Tracks camera initialization status

  DateTime? videoStartRecordingDate; // Timestamp for when video recording starts
  DateTime? videoEndRecordingDate; // Timestamp for when video recording ends

  Function(String)? onPhotoTaken; // Callback to notify when a photo is taken
  Function(String)? onVideoRecorded; // Callback to notify when a video is recorded

  // Current camera quality setting (default: high)
  CameraQuality _currentQuality = CameraQuality.high;
  @override
  CameraQuality get currentQuality => _currentQuality;

  List<CameraDescription> _availableCameras = []; // List of available cameras
  int _selectedCameraIndex = 0; // Index of the selected camera
  CameraDescription? _selectedCamera; // The currently selected camera

  /// Constructor with optional callbacks.
  MobileCameraService({this.onPhotoTaken, this.onVideoRecorded});

  /// Initializes the available cameras and selects the default camera.
  @override
  Future<void> initializeCameras() async {
    try {
      _availableCameras = await availableCameras();

      if (_availableCameras.isEmpty) {
        LogService.instance.registerLog("No cameras available on this device.");
        return;
      }

      _selectedCameraIndex = 0; // Default to the first camera
      _selectedCamera = _availableCameras[_selectedCameraIndex];
    } catch (e) {
      LogService.instance.registerLog("Error initializing cameras: $e");
    }
  }

  /// Returns a list of available cameras.
  @override
  List<CameraDescription> getAvailableCameras() {
    return _availableCameras;
  }

  /// Selects a camera by index.
  @override
  Future<void> selectCamera(int index) async {
    if (index < 0 || index >= _availableCameras.length) {
      LogService.instance.registerLog("Invalid camera index selected.");
      return;
    }

    _selectedCameraIndex = index;
    _selectedCamera = _availableCameras[_selectedCameraIndex];

    // Restart the camera with the new selection
    await startCamera();
  }

  /// Starts the camera and initializes it with default settings.
  @override
  Future<void> startCamera() async {
    // Ensure cameras are initialized
    if (_availableCameras.isEmpty) {
      await initializeCameras();
    }

    if (_selectedCamera == null) {
      LogService.instance.registerLog("No camera selected.");
      return;
    }

    final quality = await _loadCameraQuality();

    _controller = CameraController(_selectedCamera!, quality);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off at startup
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera initialized with flash off");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
    }
  }

  /// Loads stored camera setting if exists and applies it to the camera.
  Future<ResolutionPreset> _loadCameraQuality() async {
    final quality = await SettingsService.getCameraQuality();
    switch (quality) {
      case 'medium':
        _currentQuality = CameraQuality.medium;
        return ResolutionPreset.medium;
      case 'low':
        _currentQuality = CameraQuality.low;
        return ResolutionPreset.low;
      case 'high':
      default:
        _currentQuality = CameraQuality.high;
        return ResolutionPreset.high;
    }
  }

  /// Ensures the camera is ready before performing any operation.
  Future<void> ensureCameraIsReady() async {
    if (_isCameraInitialized && _controller?.value.isInitialized == true) {
      LogService.instance.registerLog("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    LogService.instance.registerLog("Initializing camera...");
    await startCamera();
  }

  /// Captures a photo and saves it to the gallery.
  @override
  Future<String> takePhoto({bool enableFlash = false}) async {
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before taking a photo

      if (enableFlash) {
        await _controller?.setFlashMode(FlashMode.torch); // Turn on flash before taking the photo
      }

      final XFile photo = await _controller!.takePicture();
      LogService.instance.registerLog("Photo taken at path: ${photo.path}");

      // Save to gallery
      await GallerySaver.saveImage(photo.path, albumName: 'HydraCam');

      if (onPhotoTaken != null) {
        onPhotoTaken!(photo.path);
      }

      if (enableFlash) {
        await _controller?.setFlashMode(FlashMode.off); // Turn off flash after taking the photo
      }

      return photo.path;
    } catch (e) {
      LogService.instance.registerLog("Error taking photo: $e");
      return "Error taking photo";
    }
  }

  /// Starts recording a video.
  @override
  Future<void> startRecordingVideo({bool enableFlash = false}) async {
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before starting video recording

      if (enableFlash) {
        await _controller?.setFlashMode(FlashMode.torch); // Turn on flash for video recording
      }

      videoStartRecordingDate = DateTime.now();
      await _controller?.startVideoRecording();
      LogService.instance.registerLog("Video recording started with flash ${enableFlash ? 'on' : 'off'}");
    } catch (e) {
      LogService.instance.registerLog("Error starting video recording: $e");
    }
  }

  /// Stops recording a video and saves it to the gallery.
  @override
  Future<String> stopRecordingVideo() async {
    try {
      final XFile video = await _controller!.stopVideoRecording();
      videoEndRecordingDate = DateTime.now();

      LogService.instance.registerLog("Video recorded at path: ${video.path}");

      // Save to gallery
      await GallerySaver.saveVideo(video.path, albumName: 'HydraCam');

      if (onVideoRecorded != null) {
        onVideoRecorded!(video.path);
      }

      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off after recording

      return video.path;
    } catch (e) {
      LogService.instance.registerLog("Error stopping video recording: $e");
      return "Error stopping video recording";
    }
  }

  /// Stops the camera and disposes of its resources.
  @override
  Future<void> stopCamera() async {
    if (_controller == null) {
      return;
    }

    try {
      await _controller?.setFlashMode(FlashMode.off); // Turn off flash when stopping the camera
      await _controller?.dispose();
      _isCameraInitialized = false;
      LogService.instance.registerLog("Camera stopped");
    } catch (e) {
      LogService.instance.registerLog("Error stopping camera: $e");
    }
  }

  /// Sets the camera quality and reinitializes the controller.
  @override
  Future<void> setCameraQuality(CameraQuality quality) async {
    LogService.instance.registerLog("Changing camera quality to $quality (current: $_currentQuality)");
    _currentQuality = quality;

    // Dispose of the current controller if initialized
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller?.dispose();
    }

    // Re-initialize the camera with the new quality
    await startCamera();
  }
}
