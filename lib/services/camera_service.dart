import "dart:io";
import "package:camera/camera.dart";
import "package:flutter/cupertino.dart";
// import "package:gallery_saver/gallery_saver.dart";  // Temporarily disabled - use photo_manager alternative
import "session_manager.dart";
import "settings_service.dart";
import "storage_service.dart";
import "gallery_persistence_service.dart";
import "package:path_provider/path_provider.dart";
import "../constants.dart";
import "../models/captured_video.dart";
import "device_service.dart";
import "log_service.dart";

/// CameraService - Manages camera operations such as taking photos and recording videos.
/// Singleton usage recommended via `CameraServiceSingleton`.
///
/// ### Responsibilities:
/// - Initializes and configures the camera.
/// - Handles photo capture and video recording with optional flash control.
/// - Saves captured media to the device's gallery.
/// - Provides callback support for notifying external components when media is captured.
/// - Exposes a `ValueNotifier<bool>` for interrupted recordings if storage is low, etc.

/// ### Features:
/// - Ensures the camera is ready before any operation.
/// - Provides an API to control flash settings during photo and video capture.
/// - Logs all operations for debugging and monitoring purposes.
/// - Supports quality settings for camera resolution.
/// - List and select available cameras for the device (WIP).
class CameraService {
  final StorageService _storageService; // Inject StorageService

  CameraController? _controller; // The camera controller instance
  CameraController? get controller =>
      _controller; // Getter for accessing the controller

  bool _isCameraInitialized = false; // Tracks camera initialization status

  DateTime?
      videoStartRecordingDate; // Timestamp for when video recording starts
  DateTime? videoEndRecordingDate; // Timestamp for when video recording ends

  /// Optional callbacks for photo/video captures.
  /// You can assign them at runtime (e.g., in `SlaveClient` or `MasterScreen`).
  Function(String)? onPhotoTaken;
  Function(String)? onVideoRecorded;

  // Current camera quality setting (default: high)
  CameraQuality _currentQuality = CameraQuality.high;

  // Notify screens of critical events, e.g., forced stop
  ValueNotifier<bool> recordingInterrupted = ValueNotifier(false);

  bool _isRecording = false; // Internal recording state
  bool get isRecording => _isRecording;

  /// List of cameras and selected one
  List<CameraDescription> _deviceCameras =
      []; // List of all available cameras on the device
  int _selectedCameraIndex = 0; // Index of the currently selected camera

  /// Constructor used only via the singleton
  /// Empty or optional for advanced use.
  CameraService(
      {required StorageService storageService,
      this.onPhotoTaken,
      this.onVideoRecorded})
      : _storageService = storageService;

  /// Returns a copy of the list of cameras (for read-only use in the UI).
  List<CameraDescription> get deviceCameras =>
      List.unmodifiable(_deviceCameras);

  /// Returns the index of the currently selected camera.
  int get selectedCameraIndex => _selectedCameraIndex;

  /// Initializes the camera service by loading the list of device cameras.
  /// This is a separate step from actually creating a CameraController.
  Future<void> initAvailableCameras() async {
    try {
      _deviceCameras = await availableCameras();
      LogService.instance.registerLog(
          "Found ${_deviceCameras.length} camera(s) on this device.");
    } catch (e) {
      LogService.instance.registerLog("Error loading available cameras: $e");
      _deviceCameras = [];
    }
  }

  /// Starts the camera and initializes it with default settings.
  ///
  /// - If no index is provided, it uses the current `_selectedCameraIndex`.
  /// - Loads previous camera setting if exists.
  /// - Ensures the flash is turned off during initialization.
  Future<void> startCamera({int? cameraIndex}) async {
    // If there's no camera on the device, exit gracefully
    if (_deviceCameras.isEmpty) {
      LogService.instance
          .registerLog("No cameras found on device. Aborting startCamera.");
      return;
    }

    // Use a provided index if any, or the existing selectedCameraIndex
    if (cameraIndex != null) {
      _selectedCameraIndex = cameraIndex;
    }

    final quality = await _loadCameraQuality();

    // Dispose any existing controller before creating a new one
    await _controller?.dispose();

    // Clamping to avoid out of range index
    if (_selectedCameraIndex >= _deviceCameras.length) {
      _selectedCameraIndex = 0;
    }

    final cameraDescription = _deviceCameras[_selectedCameraIndex];
    _controller = CameraController(cameraDescription, quality);

    try {
      await _controller?.initialize();
      await _controller
          ?.setFlashMode(FlashMode.off); // Ensure the flash is off at startup
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera initialized with flash off");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
    }
  }

  /// Loads stored camera setting if exists and applies it to camera.
  ///
  /// - Gets camera quality from settings service.
  /// - Configures found setting or high if none.
  Future<ResolutionPreset> _loadCameraQuality() async {
    final quality = await SettingsService.getCameraQuality();
    switch (quality) {
      case "medium":
        _currentQuality = CameraQuality.medium;
        return ResolutionPreset.medium;
      case "low":
        _currentQuality = CameraQuality.low;
        return ResolutionPreset.low;
      case "high":
      default:
        _currentQuality = CameraQuality.high;
        return ResolutionPreset.high;
    }
  }

  /// Changes the currently selected camera to the specified index and restarts the camera.
  Future<void> switchCamera(int newCameraIndex) async {
    if (newCameraIndex < 0 || newCameraIndex >= _deviceCameras.length) {
      LogService.instance.registerLog("Invalid camera index: $newCameraIndex");
      return;
    }

    LogService.instance.registerLog(
        "Switching camera from $_selectedCameraIndex to $newCameraIndex");
    await startCamera(cameraIndex: newCameraIndex);
  }

  /// Ensures the camera is ready before performing any operation.
  ///
  /// - Initializes the camera if it has not been initialized already.
  /// - Configures the flash to be off by default.
  /// - Throws an exception if initialization fails.
  Future<void> ensureCameraIsReady() async {
    if (_isCameraInitialized && _controller?.value.isInitialized == true) {
      LogService.instance
          .registerLog("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    LogService.instance.registerLog("Initializing camera...");
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(
          FlashMode.off); // Ensure the flash is off during initialization
      _isCameraInitialized = true;
      LogService.instance
          .registerLog("Camera successfully initialized with flash off.");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
      _isCameraInitialized = false;
      throw Exception("Failed to initialize camera: $e");
    }
  }

  /// Captures a photo and saves it to the gallery.
  ///
  /// - `enableFlash`: Whether to enable the flash during capture (default: `false`).
  /// - Returns the file path of the captured photo.
  Future<String> takePhoto({bool enableFlash = false}) async {
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before taking a photo

      if (enableFlash) {
        await _controller?.setFlashMode(
            FlashMode.torch); // Turn on flash before taking the photo
      }

      final XFile photo = await _controller!.takePicture();
      final newPath = await _getSessionMediaPath(photo.name);
      await File(photo.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Photo saved to session path: $newPath");

      await GalleryPersistenceService.savePhoto(newPath);

      if (onPhotoTaken != null) {
        onPhotoTaken!(newPath);
      }

      if (enableFlash) {
        await _controller?.setFlashMode(
            FlashMode.off); // Turn off flash after taking the photo
      }

      return newPath;
    } catch (e) {
      LogService.instance.registerLog("Error taking photo: $e");
      return "Error taking photo";
    }
  }

  /// Announces the start or end of video recording using the flash, if enabled in settings.
  Future<void> announceRecordingWithFlash() async {
    final flashEnabled = await SettingsService.getFlashForVideoAnnounce();
    if (!flashEnabled || _controller == null) return;

    // Perform a double flash: turn on torch for short period, turn off, repeat
    try {
      for (int i = 0; i < 2; i++) {
        await _controller?.setFlashMode(FlashMode.torch);
        await Future.delayed(const Duration(milliseconds: 300));
        await _controller?.setFlashMode(FlashMode.off);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      LogService.instance
          .registerLog("Performed flash announcement for video recording");
    } catch (e) {
      LogService.instance
          .registerLog("Error performing flash announcement: $e");
    }
  }

  /// Starts recording a video.
  ///
  /// - `enableFlash`: Whether to enable the flash during recording (default: `false`).
  Future<void> startRecordingVideo({bool enableFlash = false}) async {
    // Check if storage is critically low before proceeding
    if (_storageService.isRecordingBlocked) {
      LogService.instance
          .registerLog("Cannot start recording: Storage is critically low.");

      // Notify user
      _storageService.showNotification(
          "Cannot start recording: Storage is critically low.");

      return;
    }
    // Continue
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before starting video recording

      // Announce with flash before starting (if setting is enabled)
      await announceRecordingWithFlash();

      if (enableFlash) {
        await _controller?.setFlashMode(
            FlashMode.torch); // Turn on flash for video recording
      }

      videoStartRecordingDate = DateTime.now();
      await _controller?.startVideoRecording();
      LogService.instance.registerLog(
          "Video recording started with flash ${enableFlash ? 'on' : 'off'}");

      _isRecording = true;
    } catch (e) {
      LogService.instance.registerLog("Error starting video recording: $e");
      _isRecording = false;
    }
  }

  /// Stops recording a video and saves it to the gallery.
  ///
  /// - Returns the file path of the recorded video.
  Future<String> stopRecordingVideo() async {
    try {
      final XFile video = await _controller!.stopVideoRecording();
      videoEndRecordingDate = DateTime.now();

      _isRecording = false;

      final newPath = await _getSessionMediaPath(video.name);

      await File(video.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Video saved to session path: $newPath");

      // Announce with flash after stopping (if setting is enabled)
      await announceRecordingWithFlash();

      // TODO: ISOLATE FROM MAIN THREAD IF THAT INCREASES PERFORMANCE?
      LogService.instance.registerLog("Video recorded at path: $newPath");

      await GalleryPersistenceService.saveVideo(newPath);

      if (onVideoRecorded != null) {
        onVideoRecorded!(newPath);
      }

      await _controller?.setFlashMode(
          FlashMode.off); // Ensure the flash is off after recording

      return newPath;
    } catch (e) {
      LogService.instance.registerLog("Error stopping video recording: $e");
      _isRecording = false;
      return "Error stopping video recording";
    }
  }

  /// Forces stop recording in case we reached full storage
  Future<void> forceStopRecordingDueToStorage() async {
    try {
      //await Future.delayed(const Duration(seconds:10)); //TODO: wait for timer if active

      // Verify if the camera is actually recording before stopping
      if (_isRecording) {
        //TODO this for some reason resets to false
        LogService.instance
            .registerLog("Stopping recording due to critical storage.");

        // Stop recording
        final videoPath = await stopRecordingVideo();

        // Notify user
        _storageService
            .showNotification("Recording stopped due to low storage.");

        // Register video in SessionManager
        final String deviceId = await DeviceIdService.getOrCreateDeviceId();
        final capturedVideo = CapturedVideo(
          videoData: null,
          videoPath: videoPath,
          slaveDeviceId: deviceId,
          startRecordingDate: videoStartRecordingDate!,
          endRecordingDate: DateTime.now(),
          receivedDate: DateTime.now(),
        );
        SessionManager.instance.addVideo(capturedVideo);

        // Notify interruption
        recordingInterrupted.value = true;
      }
    } catch (e) {
      LogService.instance.registerLog("Error force-stopping recording: $e");
    }
  }

  /// Stops the camera and disposes of its resources.
  Future<void> stopCamera() async {
    try {
      await _controller?.setFlashMode(
          FlashMode.off); // Turn off flash when stopping the camera
      await _controller?.dispose();
      LogService.instance.registerLog("Camera stopped");
    } catch (e) {
      LogService.instance.registerLog("Error stopping camera: $e");
    }
  }

  /// Sets the camera quality and reinitializes the controller.
  Future<void> setCameraQuality(CameraQuality quality) async {
    LogService.instance.registerLog(
        "Changing camera quality to $quality (current: $_currentQuality)");
    _currentQuality = quality;

    ResolutionPreset preset;

    switch (quality) {
      case CameraQuality.high:
        preset = ResolutionPreset.high;
        break;
      case CameraQuality.medium:
        preset = ResolutionPreset.medium;
        break;
      case CameraQuality.low:
        preset = ResolutionPreset.low;
        break;
    }

    // Dispose of the current controller if initialized
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller?.dispose();
    }

    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], preset);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(FlashMode.off);
      _isCameraInitialized = true;
      LogService.instance.registerLog(
          "Camera quality set to $_currentQuality and reinitialized.");
    } catch (e) {
      LogService.instance.registerLog("Error setting camera quality: $e");
    }
  }

  /// Returns the current camera quality.
  CameraQuality get currentQuality => _currentQuality;

  /// Function to find session directory to store files
  /// Directory would be something like `/data/user/0/com.amaia23.hydracam/session_<sessionGuid>/...` in Android.
  Future<String> _getSessionMediaPath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDir = Directory(
        "${directory.path}/session_${SessionManager.instance.sessionGuid}");
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }
    return "${sessionDir.path}/$fileName";
  }
}
