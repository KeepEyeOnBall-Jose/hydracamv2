import "dart:async";
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
import "../models/camera_capture_settings.dart";
import "../models/captured_video.dart";
import "device_service.dart";
import "log_service.dart";
import "video_metadata_service.dart";

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
  final bool _useMockCamera;

  CameraController? _controller; // The camera controller instance
  CameraController? get controller =>
      _controller; // Getter for accessing the controller

  static const CameraDescription _mockCameraDescription = CameraDescription(
    name: "hydracam-macos-controller-mock",
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 0,
  );

  bool _isCameraInitialized = false; // Tracks camera initialization status
  bool? _flashAvailable;
  int _mockMediaSequence = 0;
  bool _controllerUsesExplicitFps = true;

  static const Duration _cameraOperationTimeout = Duration(seconds: 12);
  static const Duration _cameraDisposeSettleDelay = Duration(milliseconds: 400);

  DateTime?
      videoStartRecordingDate; // Timestamp for when video recording starts
  DateTime? videoEndRecordingDate; // Timestamp for when video recording ends

  /// Optional callbacks for photo/video captures.
  /// You can assign them at runtime (e.g., in `SlaveClient` or `MasterScreen`).
  Function(String)? onPhotoTaken;
  Function(String)? onVideoRecorded;

  // Current camera quality setting (default: high)
  CameraQuality _currentQuality = CameraQuality.high;
  VideoCaptureProfile _currentProfile = VideoCaptureProfile.standard1080p30;

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
      this.onVideoRecorded,
      bool? useMockCamera})
      : _storageService = storageService,
        _useMockCamera = useMockCamera ?? Platform.isMacOS;

  bool get isUsingMockCamera => _useMockCamera;

  /// Returns a copy of the list of cameras (for read-only use in the UI).
  List<CameraDescription> get deviceCameras {
    if (_useMockCamera && _deviceCameras.isEmpty) {
      return const [_mockCameraDescription];
    }
    return List.unmodifiable(_deviceCameras);
  }

  /// Returns the index of the currently selected camera.
  int get selectedCameraIndex => _selectedCameraIndex;

  /// Initializes the camera service by loading the list of device cameras.
  /// This is a separate step from actually creating a CameraController.
  Future<void> initAvailableCameras() async {
    if (_useMockCamera) {
      _deviceCameras = const [_mockCameraDescription];
      _isCameraInitialized = true;
      LogService.instance.registerLog(
          "Using mock camera for native controller mode on macOS.");
      return;
    }

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
    if (_useMockCamera) {
      await _ensureMockCameraReady();
      return;
    }

    // If there's no camera on the device, exit gracefully
    if (_deviceCameras.isEmpty) {
      LogService.instance
          .registerLog("No cameras found on device. Aborting startCamera.");
      return;
    }

    final cameraDescription = await _resolveCameraDescription(
      _deviceCameras,
      requestedIndex: cameraIndex,
    );
    final profile = await _loadVideoCaptureProfile();

    // Dispose any existing controller before creating a new one
    await _disposeController("camera startup");
    _controller = _createController(cameraDescription, profile);
    _flashAvailable = null;

    try {
      await _controller?.initialize();
      await _setFlashModeIfSupported(
          FlashMode.off, "camera startup initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera initialized");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
    }
  }

  Future<VideoCaptureProfile> _loadVideoCaptureProfile() async {
    final profile = await SettingsService.getVideoCaptureProfile();
    _currentProfile = profile;
    _currentQuality = switch (profile.resolutionPreset) {
      ResolutionPreset.medium => CameraQuality.low,
      ResolutionPreset.high => CameraQuality.medium,
      _ => CameraQuality.high,
    };
    return profile;
  }

  CameraController _createController(
    CameraDescription cameraDescription,
    VideoCaptureProfile profile,
  ) {
    _controllerUsesExplicitFps = true;
    return CameraController(
      cameraDescription,
      profile.resolutionPreset,
      fps: profile.framesPerSecond,
    );
  }

  CameraController _createControllerUsingPresetDefaults(
    CameraDescription cameraDescription,
    VideoCaptureProfile profile,
  ) {
    _controllerUsesExplicitFps = false;
    return CameraController(
      cameraDescription,
      profile.resolutionPreset,
    );
  }

  /// Changes the currently selected camera to the specified index and restarts the camera.
  Future<void> switchCamera(int newCameraIndex) async {
    if (newCameraIndex < 0 || newCameraIndex >= _deviceCameras.length) {
      LogService.instance.registerLog("Invalid camera index: $newCameraIndex");
      return;
    }

    LogService.instance.registerLog(
        "Switching camera from $_selectedCameraIndex to $newCameraIndex");
    await SettingsService.setSelectedCameraName(
      _deviceCameras[newCameraIndex].name,
    );
    await startCamera(cameraIndex: newCameraIndex);
  }

  /// Ensures the camera is ready before performing any operation.
  ///
  /// - Initializes the camera if it has not been initialized already.
  /// - Configures the flash to be off by default.
  /// - Throws an exception if initialization fails.
  Future<void> ensureCameraIsReady() async {
    if (_useMockCamera) {
      await _ensureMockCameraReady();
      return;
    }

    if (_isCameraInitialized && _controller?.value.isInitialized == true) {
      LogService.instance
          .registerLog("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    LogService.instance.registerLog("Initializing camera...");
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception("No cameras available on this device.");
    }

    _deviceCameras = cameras;
    final cameraDescription = await _resolveCameraDescription(cameras);
    final profile = await _loadVideoCaptureProfile();

    await _disposeController("camera readiness initialization");
    _controller = _createController(cameraDescription, profile);
    _flashAvailable = null;

    try {
      await _controller?.initialize();
      await _setFlashModeIfSupported(
          FlashMode.off, "camera readiness initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera successfully initialized.");
    } catch (e, stackTrace) {
      LogService.instance
          .registerLog("Error initializing camera: $e\n$stackTrace");
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
      if (_useMockCamera) {
        return await _takeMockPhoto();
      }

      await ensureCameraIsReady(); // Ensure the camera is ready before taking a photo

      if (enableFlash) {
        await _setFlashModeIfSupported(FlashMode.torch, "photo capture");
      }

      final XFile photo = await _takePictureWithFallback();
      final newPath = await _getSessionMediaPath(photo.name);
      await File(photo.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Photo saved to session path: $newPath");

      await GalleryPersistenceService.savePhoto(newPath);

      if (onPhotoTaken != null) {
        onPhotoTaken!(newPath);
      }

      if (enableFlash) {
        await _setFlashModeIfSupported(FlashMode.off, "photo capture cleanup");
      }

      return newPath;
    } catch (e, stackTrace) {
      LogService.instance.registerLog("Error taking photo: $e\n$stackTrace");
      throw Exception("Failed to take photo: $e");
    }
  }

  /// Announces the start or end of video recording using the flash, if enabled in settings.
  Future<void> announceRecordingWithFlash() async {
    final flashEnabled = await SettingsService.getFlashForVideoAnnounce();
    if (!flashEnabled || _controller == null) return;

    // Perform a double flash: turn on torch for short period, turn off, repeat
    try {
      for (int i = 0; i < 2; i++) {
        final didEnableFlash = await _setFlashModeIfSupported(
            FlashMode.torch, "video recording announcement");
        if (!didEnableFlash) {
          return;
        }
        await Future.delayed(const Duration(milliseconds: 300));
        await _setFlashModeIfSupported(
            FlashMode.off, "video recording announcement");
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

      throw Exception("Cannot start recording: Storage is critically low.");
    }
    // Continue
    try {
      if (_useMockCamera) {
        await _ensureMockCameraReady();
        videoStartRecordingDate = DateTime.now();
        videoEndRecordingDate = null;
        _isRecording = true;
        LogService.instance.registerLog(
            "Mock video recording started for native controller mode.");
        return;
      }

      await ensureCameraIsReady(); // Ensure the camera is ready before starting video recording

      // Announce with flash before starting (if setting is enabled)
      await announceRecordingWithFlash();

      if (enableFlash) {
        await _setFlashModeIfSupported(FlashMode.torch, "video recording");
      }

      final startTime = DateTime.now();
      await _startVideoRecordingWithFallback();
      videoStartRecordingDate = startTime;
      LogService.instance.registerLog(
          "Video recording started with flash ${enableFlash ? 'on' : 'off'}");

      _isRecording = true;
    } catch (e, stackTrace) {
      LogService.instance
          .registerLog("Error starting video recording: $e\n$stackTrace");
      _isRecording = false;
      videoStartRecordingDate = null;
      throw Exception("Failed to start video recording: $e");
    }
  }

  /// Stops recording a video and saves it to the gallery.
  ///
  /// - Returns the file path of the recorded video.
  Future<String> stopRecordingVideo() async {
    try {
      if (_useMockCamera) {
        return await _stopMockVideoRecording();
      }

      if (!_isRecording && !(_controller?.value.isRecordingVideo ?? false)) {
        throw Exception(
            "stopVideoRecording was called when no video is recording.");
      }

      final XFile video = await _controller!.stopVideoRecording();
      videoEndRecordingDate = DateTime.now();

      _isRecording = false;

      final newPath = await _getSessionMediaPath(video.name);

      await File(video.path).copy(newPath); // Move to session directory
      LogService.instance.registerLog("Video saved to session path: $newPath");
      await _logRecordedVideoMetadata(newPath);

      // Announce with flash after stopping (if setting is enabled)
      await announceRecordingWithFlash();

      // TODO: ISOLATE FROM MAIN THREAD IF THAT INCREASES PERFORMANCE?
      LogService.instance.registerLog("Video recorded at path: $newPath");

      await GalleryPersistenceService.saveVideo(newPath);

      if (onVideoRecorded != null) {
        onVideoRecorded!(newPath);
      }

      await _setFlashModeIfSupported(FlashMode.off, "video recording cleanup");

      return newPath;
    } catch (e, stackTrace) {
      LogService.instance
          .registerLog("Error stopping video recording: $e\n$stackTrace");
      _isRecording = _controller?.value.isRecordingVideo ?? false;
      throw Exception("Failed to stop video recording: $e");
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
      if (_useMockCamera) {
        _isCameraInitialized = false;
        LogService.instance.registerLog("Mock camera stopped");
        return;
      }

      await _setFlashModeIfSupported(FlashMode.off, "camera stop");
      await _disposeController("camera stop");
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

    final profile = switch (quality) {
      CameraQuality.high => VideoCaptureProfile.standard1080p30,
      CameraQuality.medium => VideoCaptureProfile.compat720p30,
      CameraQuality.low => VideoCaptureProfile.dataSaver480p30,
    };
    await setVideoCaptureProfile(profile);
  }

  Future<void> setVideoCaptureProfile(VideoCaptureProfile profile) async {
    LogService.instance.registerLog(
        "Changing video capture profile to ${profile.storageValue} "
        "(current: ${_currentProfile.storageValue})");
    await applyCaptureSettings(videoProfile: profile);
  }

  Future<void> setLensPreference(LensPreference preference) async {
    LogService.instance.registerLog(
        "Changing camera lens preference to ${preference.storageValue}");
    await applyCaptureSettings(
      lensPreference: preference,
      clearSelectedCameraName: true,
    );
  }

  Future<void> applyCaptureSettings({
    LensPreference? lensPreference,
    String? selectedCameraName,
    bool clearSelectedCameraName = false,
    VideoCaptureProfile? videoProfile,
  }) async {
    if (lensPreference != null) {
      await SettingsService.setCameraLensPreference(lensPreference);
    }
    if (clearSelectedCameraName) {
      await SettingsService.clearSelectedCameraName();
    } else if (selectedCameraName != null) {
      await SettingsService.setSelectedCameraName(selectedCameraName);
    }
    if (videoProfile != null) {
      _currentProfile = videoProfile;
      await SettingsService.setVideoCaptureProfile(videoProfile);
    }

    if (_useMockCamera) {
      _isCameraInitialized = true;
      LogService.instance.registerLog("Mock camera capture settings updated: "
          "lens=${lensPreference?.storageValue ?? 'unchanged'}, "
          "profile=${videoProfile?.storageValue ?? _currentProfile.storageValue}.");
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      LogService.instance
          .registerLog("No cameras found on device. Aborting settings change.");
      return;
    }

    _deviceCameras = cameras;
    final cameraDescription = await _resolveCameraDescription(cameras);
    final profile = await _loadVideoCaptureProfile();

    await _disposeController("camera settings change");
    _controller = _createController(cameraDescription, profile);
    _flashAvailable = null;

    try {
      await _controller?.initialize();
      await _setFlashModeIfSupported(FlashMode.off, "camera lens change");
      _isCameraInitialized = true;
      LogService.instance
          .registerLog("Camera capture settings applied and reinitialized: "
              "camera=${cameraDescription.name}, "
              "profile=${profile.storageValue}.");
    } catch (e) {
      LogService.instance.registerLog("Error applying camera settings: $e");
    }
  }

  /// Returns the current camera quality.
  CameraQuality get currentQuality => _currentQuality;
  VideoCaptureProfile get currentProfile => _currentProfile;

  Future<CameraDescription> _resolveCameraDescription(
    List<CameraDescription> cameras, {
    int? requestedIndex,
  }) async {
    if (requestedIndex != null) {
      _selectedCameraIndex = requestedIndex.clamp(0, cameras.length - 1);
      final selectedCamera = cameras[_selectedCameraIndex];
      await SettingsService.setSelectedCameraName(selectedCamera.name);
      return selectedCamera;
    }

    final storedCameraName = await SettingsService.getSelectedCameraName();
    if (storedCameraName != null) {
      final storedIndex = cameras.indexWhere(
        (camera) => camera.name == storedCameraName,
      );
      if (storedIndex >= 0) {
        _selectedCameraIndex = storedIndex;
        return cameras[storedIndex];
      }
    }

    final lensPreference = await SettingsService.getCameraLensPreference();
    var resolvedIndex = cameras.indexWhere(lensPreference.matches);
    if (resolvedIndex < 0 && lensPreference != LensPreference.autoBack) {
      resolvedIndex = cameras.indexWhere(LensPreference.autoBack.matches);
    }
    if (resolvedIndex < 0) {
      resolvedIndex = 0;
    }

    _selectedCameraIndex = resolvedIndex;
    await SettingsService.setSelectedCameraName(cameras[resolvedIndex].name);
    return cameras[resolvedIndex];
  }

  Future<void> _logRecordedVideoMetadata(String videoPath) async {
    try {
      final metadata = await VideoMetadataService.inspectVideo(videoPath);
      if (metadata == null) {
        LogService.instance
            .registerLog("Recorded video metadata unavailable for $videoPath");
        return;
      }
      LogService.instance.registerLog(
          "Recorded video metadata: ${metadata.width}x${metadata.height}, "
          "${metadata.framesPerSecondText} fps, "
          "${metadata.durationMs ?? 'unknown'} ms");
    } catch (e) {
      LogService.instance
          .registerLog("Error inspecting recorded video metadata: $e");
    }
  }

  Future<XFile> _takePictureWithFallback() async {
    try {
      return await _controller!.takePicture().timeout(_cameraOperationTimeout);
    } on TimeoutException catch (error, stackTrace) {
      LogService.instance.registerLog("Camera photo capture timed out after "
          "${_cameraOperationTimeout.inSeconds}s; leaving controller intact. "
          "$error\n$stackTrace");
      rethrow;
    } catch (error, stackTrace) {
      final didRecover = await _reinitializeWithoutExplicitFps(
        "photo capture",
        error,
        stackTrace,
      );
      if (!didRecover) {
        rethrow;
      }
      return await _controller!.takePicture().timeout(_cameraOperationTimeout);
    }
  }

  Future<void> _startVideoRecordingWithFallback() async {
    try {
      await _controller!.startVideoRecording().timeout(_cameraOperationTimeout);
    } on TimeoutException catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Camera video recording start timed out after "
          "${_cameraOperationTimeout.inSeconds}s; leaving controller intact. "
          "$error\n$stackTrace");
      rethrow;
    } catch (error, stackTrace) {
      final didRecover = await _reinitializeWithoutExplicitFps(
        "video recording start",
        error,
        stackTrace,
      );
      if (!didRecover) {
        rethrow;
      }
      await _controller!.startVideoRecording().timeout(_cameraOperationTimeout);
    }
  }

  Future<bool> _reinitializeWithoutExplicitFps(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_controllerUsesExplicitFps) {
      return false;
    }

    LogService.instance.registerLog(
        "Camera $operation failed with explicit fps; retrying with "
        "resolution preset defaults. Error: $error\n$stackTrace");

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        LogService.instance.registerLog(
            "No cameras found while retrying $operation without explicit fps.");
        return false;
      }

      _deviceCameras = cameras;
      final cameraDescription = await _resolveCameraDescription(cameras);
      final profile = await _loadVideoCaptureProfile();
      await _disposeController("$operation retry");
      _controller = _createControllerUsingPresetDefaults(
        cameraDescription,
        profile,
      );
      _flashAvailable = null;
      await _controller?.initialize().timeout(_cameraOperationTimeout);
      await _setFlashModeIfSupported(
          FlashMode.off, "$operation retry initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog(
          "Camera reinitialized for $operation without explicit fps: "
          "camera=${cameraDescription.name}, profile=${profile.storageValue}.");
      return true;
    } catch (retryError, retryStackTrace) {
      _isCameraInitialized = false;
      LogService.instance
          .registerLog("Camera $operation retry without explicit fps failed: "
              "$retryError\n$retryStackTrace");
      return false;
    }
  }

  Future<void> _disposeController(String operation) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    _controller = null;
    _isCameraInitialized = false;
    _flashAvailable = null;
    try {
      await controller.dispose().timeout(const Duration(seconds: 5));
    } catch (error) {
      LogService.instance.registerLog(
          "Error disposing camera controller during $operation: $error");
    }
    await Future.delayed(_cameraDisposeSettleDelay);
  }

  Future<bool> _setFlashModeIfSupported(
      FlashMode mode, String operation) async {
    final controller = _controller;
    if (controller == null || _flashAvailable == false) {
      return false;
    }

    try {
      await controller.setFlashMode(mode);
      _flashAvailable = true;
      return true;
    } on UnimplementedError catch (error) {
      _flashAvailable = false;
      LogService.instance.registerLog(
          "Flash is unavailable for $operation on this platform; continuing without flash: $error");
      return false;
    } on CameraException catch (error) {
      if (_isMissingFlashCapability(error)) {
        _flashAvailable = false;
        LogService.instance.registerLog(
            "Flash is unavailable for $operation; continuing without flash: $error");
        return false;
      }
      rethrow;
    }
  }

  bool _isMissingFlashCapability(CameraException error) {
    final description = error.description?.toLowerCase() ?? "";
    final code = error.code.toLowerCase();
    return code.contains("unimplemented") ||
        code.contains("unsupported") ||
        description.contains("not supported") ||
        description.contains("unsupported") ||
        (code == "setflashmodefailed" &&
            description.contains("flash") &&
            description.contains("capabilities"));
  }

  Future<void> _ensureMockCameraReady() async {
    _deviceCameras = const [_mockCameraDescription];
    _isCameraInitialized = true;
    LogService.instance
        .registerLog("Mock camera ready for native controller mode on macOS.");
  }

  Future<String> _takeMockPhoto() async {
    await _ensureMockCameraReady();
    final filePath = await _writeMockMediaFile(
      extension: "jpg",
      contents: "HydraCam mock photo captured at ${DateTime.now()}\n",
    );
    LogService.instance
        .registerLog("Mock photo saved to session path: $filePath");
    if (onPhotoTaken != null) {
      onPhotoTaken!(filePath);
    }
    return filePath;
  }

  Future<String> _stopMockVideoRecording() async {
    if (!_isRecording) {
      throw Exception(
          "stopVideoRecording was called when no video is recording.");
    }

    videoEndRecordingDate = DateTime.now();
    _isRecording = false;
    final start = videoStartRecordingDate ?? videoEndRecordingDate;
    final filePath = await _writeMockMediaFile(
      extension: "mp4",
      contents: "HydraCam mock video captured from $start to "
          "$videoEndRecordingDate\n",
    );
    LogService.instance
        .registerLog("Mock video saved to session path: $filePath");
    if (onVideoRecorded != null) {
      onVideoRecorded!(filePath);
    }
    return filePath;
  }

  Future<String> _writeMockMediaFile({
    required String extension,
    required String contents,
  }) async {
    _mockMediaSequence += 1;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(":", "-")
        .replaceAll(".", "-");
    final filePath = await _getSessionMediaPath(
        "mock_${_mockMediaSequence}_$timestamp.$extension");
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
    return filePath;
  }

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
