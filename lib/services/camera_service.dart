import 'dart:io';
import 'package:camera/camera.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:hydracam/services/session_manager.dart';
import 'package:hydracam/services/settings_service.dart';
import 'package:hydracam/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import '../constants.dart';
import '../models/CapturedVideo.dart';
import 'device_service.dart';
import 'log_service.dart';

/// CameraService - Manages camera operations such as taking photos and recording videos.
/// This service uses the `camera` plugin to control the device's camera, ensuring
/// consistent behavior across Android and iOS platforms.
///
/// ### Responsibilities:
/// - Initializes and configures the camera.
/// - Handles photo capture and video recording with optional flash control.
/// - Saves captured media to the device's gallery.
/// - Provides callback support for notifying external components when media is captured.
///
/// ### Features:
/// - Ensures the camera is ready before any operation.
/// - Provides an API to control flash settings during photo and video capture.
/// - Logs all operations for debugging and monitoring purposes.
/// - Supports quality settings for camera resolution.
/// - List and select available cameras for the device (TBI).
class CameraService {

  // TODO: Check if should be singleton or not, and in case not, ensure only master server and slave client interact with it, and they dispose the service after finishing with it
  CameraController? _controller; // The camera controller instance
  CameraController? get controller => _controller; // Getter for accessing the controller

  bool _isCameraInitialized = false; // Tracks camera initialization status

  DateTime? videoStartRecordingDate; // Timestamp for when video recording starts
  DateTime? videoEndRecordingDate; // Timestamp for when video recording ends

  Function(String)? onPhotoTaken; // Callback to notify screen about taken photos
  Function(String)? onVideoRecorded; // Callback to notify screen about videos

  // Current camera quality setting (default: high)
  CameraQuality _currentQuality = CameraQuality.high;

  /// Constructor that allows optional callbacks for photo and video capture.
  CameraService({this.onPhotoTaken, this.onVideoRecorded});

  /// Starts the camera and initializes it with default settings.
  ///
  /// - Uses the first available camera (usually the back camera).
  /// - Loads previous camera setting if exists.
  /// - Ensures the flash is turned off during initialization.
  Future<void> startCamera() async {
    final cameras = await availableCameras();
    final quality = await _loadCameraQuality();

    _controller = CameraController(cameras[0], quality);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off at startup
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
  ///
  /// - Initializes the camera if it has not been initialized already.
  /// - Configures the flash to be off by default.
  /// - Throws an exception if initialization fails.
  Future<void> ensureCameraIsReady() async {
    if (_isCameraInitialized && _controller?.value.isInitialized == true) {
      LogService.instance.registerLog("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    LogService.instance.registerLog("Initializing camera...");
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off during initialization
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera successfully initialized with flash off.");
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
        await _controller?.setFlashMode(FlashMode.torch); // Turn on flash before taking the photo
      }

      final XFile photo = await _controller!.takePicture();
      final newPath = await _getSessionMediaPath(photo.name);
      await File(photo.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Photo saved to session path: $newPath");

      // Save to gallery
      await GallerySaver.saveImage(newPath, albumName: 'HydraCam');

      if (onPhotoTaken != null) {
        onPhotoTaken!(newPath);
      }

      if (enableFlash) {
        await _controller?.setFlashMode(FlashMode.off); // Turn off flash after taking the photo
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
      LogService.instance.registerLog("Performed flash announcement for video recording");
    } catch (e) {
      LogService.instance.registerLog("Error performing flash announcement: $e");
    }
  }

  /// Starts recording a video.
  ///
  /// - `enableFlash`: Whether to enable the flash during recording (default: `false`).
  Future<void> startRecordingVideo({bool enableFlash = false}) async {
    // Check if storage is critically low before proceeding
    if (StorageService.isRecordingBlocked) {
      LogService.instance.registerLog("Cannot start recording: Storage is critically low.");

      // Notify user
      StorageService.showNotification("Cannot start recording: Storage is critically low.");

      return;
    }
    // Continue
    try {
      await ensureCameraIsReady(); // Ensure the camera is ready before starting video recording

      // Announce with flash before starting (if setting is enabled)
      await announceRecordingWithFlash();

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
  ///
  /// - Returns the file path of the recorded video.
  Future<String> stopRecordingVideo() async {
    try {
      final XFile video = await _controller!.stopVideoRecording();
      videoEndRecordingDate = DateTime.now();

      final newPath = await _getSessionMediaPath(video.name);
      await File(video.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Video saved to session path: $newPath");

      // Announce with flash after stopping (if setting is enabled)
      await announceRecordingWithFlash();

      // TODO: ISOLATE FROM MAIN THREAD IF THAT INCREASES PERFORMANCE?
      LogService.instance.registerLog("Video recorded at path: ${newPath}");

      // Save to gallery
      await GallerySaver.saveVideo(newPath, albumName: 'HydraCam');

      if (onVideoRecorded != null) {
        onVideoRecorded!(newPath);
      }

      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off after recording

      return newPath;
    } catch (e) {
      LogService.instance.registerLog("Error stopping video recording: $e");
      return "Error stopping video recording";
    }
  }

  /// Forces stop recording in case we reached full storage
  Future<void> forceStopRecordingDueToStorage() async {
    try {
      // Verify if the camera is actually recording before stopping
      if (_controller != null && _controller!.value.isRecordingVideo) {
        LogService.instance.registerLog("Stopping recording due to critical storage.");

        // Stop recording
        final videoPath = await stopRecordingVideo();

        // Notify user
        StorageService.showNotification("Recording stopped due to low storage.");

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
      }
    } catch (e) {
      LogService.instance.registerLog("Error force-stopping recording: $e");
    }
  }


  /// Stops the camera and disposes of its resources.
  Future<void> stopCamera() async {
    try {
      await _controller?.setFlashMode(FlashMode.off); // Turn off flash when stopping the camera
      await _controller?.dispose();
      LogService.instance.registerLog("Camera stopped");
    } catch (e) {
      LogService.instance.registerLog("Error stopping camera: $e");
    }
  }

  /// Sets the camera quality and reinitializes the controller.
  Future<void> setCameraQuality(CameraQuality quality) async {
    LogService.instance.registerLog("Changing camera quality to $quality (current: $_currentQuality)");
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
      LogService.instance.registerLog("Camera quality set to $_currentQuality and reinitialized.");
    } catch (e) {
      LogService.instance.registerLog("Error setting camera quality: $e");
    }
  }

  /// Returns the current camera quality.
  CameraQuality get currentQuality => _currentQuality;


  /// Function to find session directory to store files
  /// Directory would be something like /data/user/0/com.amaia23.hydracam/session_<<sessionGuid>>/... in android
  Future<String> _getSessionMediaPath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDir = Directory('${directory.path}/session_${SessionManager.instance.sessionGuid}');
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }
    return '${sessionDir.path}/$fileName';
  }

}
