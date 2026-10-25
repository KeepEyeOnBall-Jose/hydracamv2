import "dart:async";
import "dart:io";
import "package:camera/camera.dart";
import "package:camera_android_camerax/camera_android_camerax.dart";
import "package:camera_platform_interface/camera_platform_interface.dart"
    show CameraPlatform;
import "package:flutter/cupertino.dart";
import "package:flutter/services.dart";
import "package:uuid/uuid.dart";
import "session_manager.dart";
import "settings_service.dart";
import "storage_service.dart";
import "gallery_persistence_service.dart";
import "package:path_provider/path_provider.dart";
import "../constants.dart";
import "../models/camera_capture_settings.dart";
import "../models/capture_context_metadata.dart";
import "../models/captured_video.dart";
import "camera_compatibility_policy.dart";
import "camera_setup_service.dart";
import "device_service.dart";
import "log_service.dart";
import "manual_exposure_service.dart";
import "recorded_video_snapshots.dart";
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
  final String _mockMediaSourceDir;
  final CameraDeviceInfoProvider _deviceInfoProvider;
  final Future<String> Function() _deviceIdProvider;
  final Duration _cameraOperationTimeout;
  final ManualExposureService _manualExposureService;
  final RecordedVideoSnapshots _recordedVideoSnapshots;
  RecordingExposureSession? _recordingExposure;
  ({
    CameraDescription camera,
    VideoCaptureProfile profile,
    bool explicitFps
  })? _exposureCameraOrigin;
  bool _exposureOwnerWasDisposed = false;
  Future<void>? _exposureRecoveryInFlight;
  _OwnedVideoAttempt? _videoAttempt;
  int _captureEpoch = 0;
  Future<void>? _hardwareClosing;
  Future<void>? _cameraStopInFlight;

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
  CameraCompatibilityPolicy? _compatibilityPolicy;

  static const Duration defaultCameraOperationTimeout = Duration(seconds: 12);
  static const Duration _cameraDisposeSettleDelay = Duration(milliseconds: 400);

  DateTime?
      videoStartRecordingDate; // Timestamp for when video recording starts
  DateTime? videoEndRecordingDate; // Timestamp for when video recording ends
  MediaCaptureContext? lastPhotoCaptureContext;
  MediaCaptureContext? recordingCaptureContext;

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
      bool? useMockCamera,
      String? mockMediaSourceDir,
      CameraDeviceInfoProvider? deviceInfoProvider,
      Future<String> Function()? deviceIdProvider,
      Duration? cameraOperationTimeout,
      ManualExposureService? manualExposureService,
      RecordedVideoSnapshots? recordedVideoSnapshots})
      : _storageService = storageService,
        _manualExposureService =
            manualExposureService ?? ManualExposureService(),
        _recordedVideoSnapshots =
            recordedVideoSnapshots ?? RecordedVideoSnapshots(),
        _useMockCamera = useMockCamera ?? false,
        _deviceInfoProvider =
            deviceInfoProvider ?? DeviceIdService.getDeviceInfo,
        _deviceIdProvider =
            deviceIdProvider ?? DeviceIdService.getOrCreateDeviceId,
        _cameraOperationTimeout =
            cameraOperationTimeout ?? defaultCameraOperationTimeout,
        _mockMediaSourceDir = mockMediaSourceDir ??
            const String.fromEnvironment(
              "HYDRACAM_MOCK_MEDIA_SOURCE_DIR",
              defaultValue: "",
            );

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
          "Using mock camera because HYDRACAM_MOCK_CAMERA is enabled.");
      return;
    }

    try {
      _deviceCameras = await availableCameras();
      LogService.instance.registerLog(
          "Found ${_deviceCameras.length} camera(s) on this device.");
    } catch (e) {
      LogService.instance.registerLog("Error loading available cameras: $e");
      _deviceCameras = [];
      _isCameraInitialized = false;
    }
  }

  /// Starts the camera and initializes it with default settings.
  ///
  /// - If no index is provided, it uses the current `_selectedCameraIndex`.
  /// - Loads previous camera setting if exists.
  /// - Ensures the flash is turned off during initialization.
  Future<void> startCamera({int? cameraIndex}) async {
    await _cameraStopInFlight;
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
    final policy = await _loadCompatibilityPolicy();

    // Dispose any existing controller before creating a new one
    await _disposeController("camera startup");
    _controller = _createControllerForPolicy(
      cameraDescription,
      profile,
      policy,
      requireExplicitFps: true,
    );
    _flashAvailable = null;

    try {
      await _controller?.initialize();
      await _setFlashModeIfSupported(
          FlashMode.off, "camera startup initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog("Camera initialized");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
      _isCameraInitialized = false;
      await _controller?.dispose();
      _controller = null;
      _flashAvailable = null;
    }
  }

  Future<VideoCaptureProfile> _loadVideoCaptureProfile() async {
    final storedProfile = await SettingsService.getVideoCaptureProfile();
    final policy = await _loadCompatibilityPolicy();
    final profile = policy.resolveProfile(storedProfile);
    if (profile != storedProfile) {
      LogService.instance.registerLog(
          "${policy.reason ?? 'Camera compatibility mode'} overriding "
          "video profile ${storedProfile.storageValue} -> "
          "${profile.storageValue}.");
    }
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

  CameraController _createControllerForPolicy(
    CameraDescription cameraDescription,
    VideoCaptureProfile profile,
    CameraCompatibilityPolicy policy, {
    required bool requireExplicitFps,
  }) {
    if (!requireExplicitFps || policy.usePresetDefaultFps) {
      if (policy.usePresetDefaultFps) {
        LogService.instance.registerLog(
            "${policy.reason ?? 'Camera compatibility mode'} using platform "
            "default fps for camera controller.");
      }
      return _createControllerUsingPresetDefaults(cameraDescription, profile);
    }

    return _createController(cameraDescription, profile);
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
  Future<void> ensureCameraIsReady({bool requireExplicitFps = true}) =>
      _ensureCameraIsReady(requireExplicitFps: requireExplicitFps);

  Future<void> _ensureCameraIsReady({
    bool requireExplicitFps = true,
    bool duringRecordingStart = false,
  }) async {
    if (_useMockCamera) {
      await _ensureMockCameraReady();
      return;
    }

    final policy = await _loadCompatibilityPolicy();
    final effectiveRequireExplicitFps =
        requireExplicitFps && !policy.usePresetDefaultFps;

    if (_isCameraInitialized &&
        _controller?.value.isInitialized == true &&
        (!effectiveRequireExplicitFps || _controllerUsesExplicitFps)) {
      LogService.instance
          .registerLog("Camera is already initialized and ready.");
      return; // Camera is already ready
    }

    _requireNoCaptureReconfiguration(
        duringRecordingStart: duringRecordingStart);
    await _settleExposureBeforeReuse();
    LogService.instance.registerLog(requireExplicitFps
        ? "Initializing camera..."
        : "Initializing camera preview...");
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception("No cameras available on this device.");
    }

    _deviceCameras = cameras;
    final cameraDescription = await _resolveCameraDescription(cameras);
    final profile = await _loadVideoCaptureProfile();

    await _disposeController("camera readiness initialization",
        duringRecordingStart: duringRecordingStart);
    _controller = _createControllerForPolicy(
      cameraDescription,
      profile,
      policy,
      requireExplicitFps: effectiveRequireExplicitFps,
    );
    _flashAvailable = null;

    try {
      await _controller?.initialize();
      await _setFlashModeIfSupported(
          FlashMode.off, "camera readiness initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog(requireExplicitFps
          ? "Camera successfully initialized."
          : "Camera preview successfully initialized without explicit fps.");
    } catch (e, stackTrace) {
      LogService.instance
          .registerLog("Error initializing camera: $e\n$stackTrace");
      _isCameraInitialized = false;
      throw Exception("Failed to initialize camera: $e");
    }
  }

  /// Prepares a local setup preview without pinning an explicit FPS.
  ///
  /// Older Android camera stacks can report successful initialization and then
  /// fail asynchronously when CameraX reopens a constrained stream. Setup
  /// preview only needs a live placement surface, so it uses the selected
  /// resolution preset with platform-default frame timing. Photo/video capture
  /// still calls [ensureCameraIsReady] with explicit FPS before recording.
  Future<void> prepareCameraPreview() async {
    await ensureCameraIsReady(requireExplicitFps: false);
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
      lastPhotoCaptureContext = await _buildCurrentCaptureContext();

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
  Future<void>? _recordingStartInFlight;
  Future<String>? _recordingStopInFlight;

  Future<void> startRecordingVideo({bool enableFlash = false}) {
    final inFlight = _recordingStartInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<void> starting;
    starting = _startRecordingVideo(enableFlash: enableFlash).whenComplete(() {
      if (identical(_recordingStartInFlight, starting)) {
        _recordingStartInFlight = null;
      }
    });
    _recordingStartInFlight = starting;
    return starting;
  }

  Future<void> _startRecordingVideo({required bool enableFlash}) async {
    final cameraStop = _cameraStopInFlight;
    if (cameraStop != null) {
      await cameraStop;
    }
    final epoch = _captureEpoch;
    // Capture the operation present at entry: a later stop may itself be
    // waiting for this start, so never create a cycle between their futures.
    final stopping = _recordingStopInFlight;
    if (stopping != null) {
      await stopping;
    }
    if (_isRecording || _videoAttempt != null) {
      throw StateError("A video recording is already active");
    }
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
        recordingCaptureContext = await _buildCurrentCaptureContext();
        videoStartRecordingDate = DateTime.now();
        videoEndRecordingDate = null;
        _isRecording = true;
        LogService.instance.registerLog(
            "Mock video recording started for native controller mode.");
        return;
      }

      // Restore the previous recording before replacing or configuring its
      // camera, including when the next recording requests automatic exposure.
      await _settleExposureBeforeReuse();
      if (epoch != _captureEpoch) {
        throw StateError("Camera start was cancelled by hardware stop");
      }
      await _ensureCameraIsReady(duringRecordingStart: true);
      recordingCaptureContext = await _buildCurrentCaptureContext();

      // Announce with flash before starting (if setting is enabled)
      await announceRecordingWithFlash();

      if (enableFlash) {
        await _setFlashModeIfSupported(FlashMode.torch, "video recording");
      }

      await _lockRecordingExposure();
      if (epoch != _captureEpoch) {
        throw StateError("Camera start was cancelled by hardware stop");
      }
      final startTime = await _startVideoRecordingWithFallback();
      if (epoch != _captureEpoch) {
        throw StateError("Camera start was cancelled by hardware stop");
      }
      videoStartRecordingDate = startTime;
      _recordingExposure?.afterStart();
      LogService.instance.registerLog(
          "Video recording started with flash ${enableFlash ? 'on' : 'off'}");

      _isRecording = true;
    } catch (e, stackTrace) {
      LogService.instance
          .registerLog("Error starting video recording: $e\n$stackTrace");
      // A rejected/timed-out start may have already changed native state.
      // Keep its original operation until STOP confirms terminal settlement.
      _isRecording = _videoAttempt != null;
      if (_videoAttempt == null) {
        videoStartRecordingDate = null;
        recordingCaptureContext = null;
        await _abortRecordingExposure();
      }
      throw Exception("Failed to start video recording: $e");
    }
  }

  /// Stops recording a video and saves it to the gallery.
  ///
  /// - Returns the file path of the recorded video.
  Future<String> stopRecordingVideo() {
    final inFlight = _recordingStopInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<String> stopping;
    stopping = _stopRecordingVideo().whenComplete(() {
      if (identical(_recordingStopInFlight, stopping)) {
        _recordingStopInFlight = null;
      }
    });
    _recordingStopInFlight = stopping;
    return stopping;
  }

  Future<String> _stopRecordingVideo() async {
    try {
      if (_useMockCamera) {
        return await _stopMockVideoRecording();
      }

      if (_videoAttempt == null && _recordingStartInFlight != null) {
        await _recordingStartInFlight!.timeout(_cameraOperationTimeout);
      }
      final attempt = _videoAttempt;
      if (attempt == null) {
        throw Exception(
            "stopVideoRecording was called when no video is recording.");
      }

      final newPath =
          await _settleVideoAttempt(attempt).timeout(_cameraOperationTimeout);
      LogService.instance.registerLog("Video saved to session path: $newPath");
      await _logRecordedVideoMetadata(newPath);

      // Announce with flash after stopping (if setting is enabled)
      await announceRecordingWithFlash();

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
      _isRecording = _videoAttempt != null;
      if (_videoAttempt == null) {
        await _abortRecordingExposure();
      }
      throw Exception("Failed to stop video recording: $e");
    }
  }

  Future<RecordedVideoSnapshot> snapshotForRecordedVideo(String path) async {
    final snapshot = await _recordedVideoSnapshots.forPath(path);
    if (snapshot == null) {
      throw StateError("Original capture metadata is unavailable for $path");
    }
    return snapshot;
  }

  Future<void> acknowledgeRecordedVideo(RecordedVideoSnapshot snapshot) =>
      _recordedVideoSnapshots.acknowledge(snapshot);

  Duration _remaining(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<String> _settleVideoAttempt(_OwnedVideoAttempt attempt) {
    final existing = attempt.settlement;
    if (existing != null) {
      return existing;
    }
    late final Future<String> settling;
    settling = _finalizeVideoAttempt(attempt).whenComplete(() {
      if (!attempt.terminal && identical(attempt.settlement, settling)) {
        attempt.settlement = null;
      }
    });
    attempt.settlement = settling;
    return settling;
  }

  Future<String> _finalizeVideoAttempt(_OwnedVideoAttempt attempt) async {
    final sensor = attempt.exposure?.readBeforeStop();
    XFile video;
    try {
      if (!attempt.supportsPostDisposeStop) {
        // AVFoundation's stop ignores cameraId. Never send it after disposal,
        // even when the original start replies after our caller's deadline.
        try {
          await attempt.rawStart;
        } catch (_) {}
        if (attempt.disposed) {
          throw StateError("Original native camera was closed before STOP");
        }
      }
      video = await attempt.platform.stopVideoRecording(attempt.cameraId);
      attempt.terminal = true;
      // Consume the original public controller completion before updating its
      // notifier or permitting another dispatch on that same controller.
      try {
        await attempt.rawStart;
      } catch (_) {}
    } catch (error) {
      final code = error is CameraException
          ? error.code
          : error is PlatformException
              ? error.code
              : null;
      if (code == "RECORDING_NOT_STARTED" ||
          code == "RECORDING_FINALIZED_WITHOUT_PATH") {
        attempt.terminal = true;
        try {
          await attempt.rawStart;
        } catch (_) {}
        await _completeVideoExposure(attempt, sensor);
        _clearTerminalVideoAttempt(attempt);
      }
      rethrow;
    }
    attempt.stoppedAt = DateTime.now();
    await _completeVideoExposure(attempt, sensor);
    final captured = RecordedVideoSnapshot.capture(
        captureId: attempt.captureId,
        path: video.path,
        startedAt: attempt.startedAt,
        stoppedAt: attempt.stoppedAt,
        context: attempt.context,
        sessionGuid: attempt.sessionGuid);
    try {
      // Persist a clearly pending receipt first. Late STOP with no String
      // consumer still leaves original media and its exact metadata reachable.
      await _recordedVideoSnapshots.remember(captured);
      final path =
          await _getMediaPathForSession(video.name, attempt.sessionGuid);
      if (path != video.path) {
        await File(video.path).copy(path);
      }
      await _recordedVideoSnapshots.remember(captured.atPath(path));
      return path;
    } finally {
      _clearTerminalVideoAttempt(attempt);
    }
  }

  Future<void> _completeVideoExposure(
      _OwnedVideoAttempt attempt, Future<void>? sensor) async {
    if (sensor != null) {
      await sensor;
    }
    final exposure = attempt.exposure;
    if (exposure != null) {
      final metadata = await exposure.finish();
      attempt.context = attempt.context?.withExposure(metadata);
      LogService.instance.registerLog(
          "Recorded exposure ${metadata.preset} (${metadata.lockStatus}): "
          "exposureTimeNs=${metadata.exposureTimeNs} iso=${metadata.iso} "
          "frameDurationNs=${metadata.frameDurationNs} "
          "rollingShutterSkewNs=${metadata.rollingShutterSkewNs} "
          "underexposed=${metadata.underexposed} "
          "cameraId=${metadata.start?["cameraId"] ?? metadata.stop?["cameraId"]}");
      if (identical(_recordingExposure, exposure) && !exposure.cleanupPending) {
        _recordingExposure = null;
        _exposureCameraOrigin = null;
        _exposureOwnerWasDisposed = false;
      }
    }
    videoStartRecordingDate = attempt.startedAt;
    videoEndRecordingDate = attempt.stoppedAt;
    recordingCaptureContext = attempt.context;
  }

  void _clearTerminalVideoAttempt(_OwnedVideoAttempt attempt) {
    if (attempt.terminal && identical(_videoAttempt, attempt)) {
      if (!attempt.disposed) {
        attempt.controller.value = attempt.controller.value
            .copyWith(isRecordingVideo: false, isRecordingPaused: false);
      }
      _videoAttempt = null;
      _isRecording = false;
    }
  }

  /// Forces stop recording in case we reached full storage
  Future<void> forceStopRecordingDueToStorage() async {
    await _forceStopRecording(
      logMessage: "Stopping recording due to critical storage.",
      notificationMessage: "Recording stopped due to low storage.",
      errorLogPrefix: "Error force-stopping recording",
    );
  }

  /// Forces stop recording in case battery becomes critically low.
  Future<void> forceStopRecordingDueToBattery() async {
    await _forceStopRecording(
      logMessage: "Stopping recording due to critical battery.",
      notificationMessage: "Recording stopped due to critical battery.",
      errorLogPrefix: "Error force-stopping recording due to battery",
    );
  }

  Future<void> _forceStopRecording({
    required String logMessage,
    required String notificationMessage,
    required String errorLogPrefix,
  }) async {
    try {
      if (_isRecording) {
        LogService.instance.registerLog(logMessage);
        final videoPath = await stopRecordingVideo();
        _storageService.showNotification(notificationMessage);
        await _persistForcedStopCapturedVideo(videoPath);
        recordingInterrupted.value = true;
      }
    } catch (e) {
      LogService.instance.registerLog("$errorLogPrefix: $e");
    }
  }

  Future<void> _persistForcedStopCapturedVideo(String videoPath) async {
    final snapshot = await snapshotForRecordedVideo(videoPath);
    if (snapshot.sessionGuid != SessionManager.instance.sessionGuid) {
      throw StateError("Original clip belongs to a different session");
    }
    final String deviceId = await _deviceIdProvider();
    if (snapshot.sessionGuid == null ||
        snapshot.sessionGuid != SessionManager.instance.sessionGuid) {
      throw StateError("Original clip belongs to a different session");
    }
    final capturedVideo = _buildForcedStopCapturedVideo(
      videoPath: videoPath,
      deviceId: deviceId,
      snapshot: snapshot,
    );
    await SessionManager.instance.addVideo(capturedVideo);
    await acknowledgeRecordedVideo(snapshot);
  }

  CapturedVideo _buildForcedStopCapturedVideo({
    required String videoPath,
    required String deviceId,
    required RecordedVideoSnapshot snapshot,
  }) {
    final endRecordingDate = snapshot.stoppedAt ?? DateTime.now();
    final startRecordingDate = snapshot.startedAt ?? endRecordingDate;
    if (snapshot.startedAt == null) {
      LogService.instance.registerLog(
          "Recording start timestamp was missing during forced stop; "
          "using end timestamp as fallback.");
    }

    return CapturedVideo(
      videoData: null,
      videoPath: videoPath,
      slaveDeviceId: deviceId,
      startRecordingDate: startRecordingDate,
      endRecordingDate: endRecordingDate,
      receivedDate: DateTime.now(),
      captureContext: snapshot.context,
    );
  }

  /// Stops the camera and disposes of its resources.
  Future<void> stopCamera() {
    final existing = _cameraStopInFlight;
    if (existing != null) {
      return existing;
    }
    late final Future<void> stopping;
    stopping = _stopCamera().whenComplete(() {
      if (identical(_cameraStopInFlight, stopping)) {
        _cameraStopInFlight = null;
      }
    });
    _cameraStopInFlight = stopping;
    return stopping;
  }

  Future<void> _stopCamera() async {
    ++_captureEpoch;
    final deadline = DateTime.now().add(_cameraOperationTimeout);
    try {
      if (_useMockCamera) {
        _isCameraInitialized = false;
        LogService.instance.registerLog("Mock camera stopped");
        return;
      }

      var attempt = _videoAttempt;
      if (attempt == null && _recordingStartInFlight != null) {
        try {
          await _recordingStartInFlight!.timeout(_remaining(deadline));
        } catch (_) {
          // A before-dispatch cancellation has no recorder. A dispatched
          // operation remains retained independently from the UI start call.
        }
        attempt = _videoAttempt;
      }
      if (attempt != null) {
        try {
          await _settleVideoAttempt(attempt).timeout(_remaining(deadline));
        } catch (error) {
          LogService.instance.registerLog(
              "Recorder settlement remains pending during camera stop: $error");
        }
      }
      if (_recordingExposure?.cleanupPending ?? false) {
        _exposureOwnerWasDisposed = true;
      }
      // Explicit hardware stop must not depend on an exposure acknowledgement.
      // Keep the original lease and operation for controlled recovery later.
      if (attempt != null) {
        attempt.disposed = true;
      }
      await _disposeController("camera stop",
          allowUnsettledExposure: true, deadline: deadline);
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
    _requireNoCaptureReconfiguration();
    await _settleExposureBeforeReuse();
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
    final policy = await _loadCompatibilityPolicy();

    await _disposeController("camera settings change");
    _controller = _createControllerForPolicy(
      cameraDescription,
      profile,
      policy,
      requireExplicitFps: true,
    );
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
      final didRecover = await _reinitializeAfterTimedOutPhoto(
        error,
        stackTrace,
      );
      if (didRecover) {
        return await _controller!
            .takePicture()
            .timeout(_cameraOperationTimeout);
      }
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

  Future<DateTime> _startVideoRecordingWithFallback() async {
    final first = _dispatchVideoStart();
    try {
      await first.rawStart.timeout(_cameraOperationTimeout);
      return first.startedAt;
    } on TimeoutException catch (error, stackTrace) {
      LogService.instance.registerLog(
          "Camera video recording start timed out after "
          "${_cameraOperationTimeout.inSeconds}s; leaving controller intact. "
          "$error\n$stackTrace");
      rethrow;
    } catch (error, stackTrace) {
      // A start error alone is not proof that no encoder exists. Consume an
      // actual native terminal acknowledgement before replacing its camera.
      try {
        await _settleVideoAttempt(first).timeout(_cameraOperationTimeout);
      } catch (_) {}
      if (!first.terminal) {
        rethrow;
      }
      if (!_controllerUsesExplicitFps) {
        rethrow;
      }
      await _abortRecordingExposure(requireReleased: true);
      final didRecover = await _reinitializeWithoutExplicitFps(
        "video recording start",
        error,
        stackTrace,
        duringRecordingStart: true,
      );
      if (!didRecover) {
        rethrow;
      }
      recordingCaptureContext = await _buildCurrentCaptureContext();
      await _lockRecordingExposure();
      final retry = _dispatchVideoStart();
      await retry.rawStart.timeout(_cameraOperationTimeout);
      return retry.startedAt;
    }
  }

  _OwnedVideoAttempt _dispatchVideoStart() {
    final controller = _controller!;
    final platform = CameraPlatform.instance;
    final attempt = _OwnedVideoAttempt(
        controller: controller,
        platform: platform,
        cameraId: controller.cameraId,
        captureId: _recordingExposure?.ownerId ?? const Uuid().v4(),
        exposure: _recordingExposure,
        context: recordingCaptureContext,
        startedAt: DateTime.now(),
        sessionGuid: SessionManager.instance.sessionGuid,
        supportsPostDisposeStop:
            platform is CameraRecordingSettlementAfterDispose);
    _videoAttempt = attempt;
    attempt.rawStart = controller.startVideoRecording();
    // The original future remains retained when its bounded caller returns.
    // Install an observer now so a late rejection is never unhandled.
    unawaited(attempt.rawStart.then<void>((_) {}, onError: (Object _) {}));
    return attempt;
  }

  Future<bool> _reinitializeAfterTimedOutPhoto(
    TimeoutException error,
    StackTrace stackTrace,
  ) async {
    final policy = await _loadCompatibilityPolicy();
    if (!policy.retryTimedOutPhotoAfterReinitialize) {
      return false;
    }

    LogService.instance.registerLog("Camera photo capture timed out after "
        "${_cameraOperationTimeout.inSeconds}s; retrying after controller "
        "reinitialization for ${policy.reason ?? 'camera compatibility mode'}. "
        "$error\n$stackTrace");

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        LogService.instance.registerLog(
            "No cameras found while retrying timed-out photo capture.");
        return false;
      }

      _deviceCameras = cameras;
      final cameraDescription = await _resolveCameraDescription(cameras);
      final profile = await _loadVideoCaptureProfile();
      await _disposeController("photo timeout compatibility retry");
      await Future.delayed(_cameraDisposeSettleDelay);
      _controller = _createControllerUsingPresetDefaults(
        cameraDescription,
        profile,
      );
      _flashAvailable = null;
      await _controller?.initialize().timeout(_cameraOperationTimeout);
      await _setFlashModeIfSupported(
          FlashMode.off, "photo timeout compatibility retry initialization");
      _isCameraInitialized = true;
      LogService.instance.registerLog(
          "Camera reinitialized after timed-out photo capture: "
          "camera=${cameraDescription.name}, profile=${profile.storageValue}.");
      return true;
    } catch (retryError, retryStackTrace) {
      _isCameraInitialized = false;
      LogService.instance
          .registerLog("Camera timed-out photo compatibility retry failed: "
              "$retryError\n$retryStackTrace");
      return false;
    }
  }

  Future<bool> _reinitializeWithoutExplicitFps(
    String operation,
    Object error,
    StackTrace stackTrace, {
    bool duringRecordingStart = false,
  }) async {
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
      await _disposeController("$operation retry",
          duringRecordingStart: duringRecordingStart);
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

  Future<CameraCompatibilityPolicy> _loadCompatibilityPolicy() async {
    final cachedPolicy = _compatibilityPolicy;
    if (cachedPolicy != null) {
      return cachedPolicy;
    }

    if (_useMockCamera) {
      _compatibilityPolicy = CameraCompatibilityPolicy.none;
      return _compatibilityPolicy!;
    }

    try {
      final deviceInfo = await _deviceInfoProvider();
      final policy =
          CameraCompatibilityPolicyResolver.fromDeviceInfo(deviceInfo);
      _compatibilityPolicy = policy;
      if (policy.isActive) {
        LogService.instance.registerLog(policy.reason ??
            "Camera compatibility mode enabled for this device.");
      }
      return policy;
    } catch (error, stackTrace) {
      _compatibilityPolicy = CameraCompatibilityPolicy.none;
      LogService.instance.registerLog(
          "Unable to resolve camera compatibility policy; using defaults: "
          "$error\n$stackTrace");
      return _compatibilityPolicy!;
    }
  }

  Future<void> _disposeController(String operation,
      {bool allowUnsettledExposure = false,
      bool duringRecordingStart = false,
      DateTime? deadline}) async {
    if (!allowUnsettledExposure) {
      _requireNoCaptureReconfiguration(
          duringRecordingStart: duringRecordingStart);
      await _settleExposureBeforeReuse();
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }

    _controller = null;
    _isCameraInitialized = false;
    _flashAvailable = null;
    try {
      final closing = controller.dispose();
      _hardwareClosing = closing;
      unawaited(closing.then<void>((_) {
        if (identical(_hardwareClosing, closing)) {
          _hardwareClosing = null;
        }
      }, onError: (Object _) {}));
      await closing.timeout(
          deadline == null ? const Duration(seconds: 5) : _remaining(deadline));
    } catch (error) {
      LogService.instance.registerLog(
          "Error disposing camera controller during $operation: $error");
    }
    final settle =
        deadline == null ? _cameraDisposeSettleDelay : _remaining(deadline);
    if (settle > Duration.zero) {
      await Future.delayed(settle < _cameraDisposeSettleDelay
          ? settle
          : _cameraDisposeSettleDelay);
    }
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
    lastPhotoCaptureContext = await _buildCurrentCaptureContext();
    final filePath = await _copyConfiguredMockMediaFile(
          extension: "jpg",
          sourceFileNames: const ["mock_photo.jpg", "photo.jpg"],
        ) ??
        await _writeMockMediaFile(
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
    final filePath = await _copyConfiguredMockMediaFile(
          extension: "mp4",
          sourceFileNames: const ["mock_video.mp4", "video.mp4"],
        ) ??
        await _writeMockMediaFile(
          extension: "mp4",
          contents: "HydraCam mock video captured from $start to "
              "$videoEndRecordingDate\n",
        );
    await _recordedVideoSnapshots.remember(RecordedVideoSnapshot.capture(
        captureId: const Uuid().v4(),
        path: filePath,
        startedAt: videoStartRecordingDate,
        stoppedAt: videoEndRecordingDate,
        context: recordingCaptureContext,
        sessionGuid: SessionManager.instance.sessionGuid));
    LogService.instance
        .registerLog("Mock video saved to session path: $filePath");
    if (onVideoRecorded != null) {
      onVideoRecorded!(filePath);
    }
    return filePath;
  }

  Future<String?> _copyConfiguredMockMediaFile({
    required String extension,
    required List<String> sourceFileNames,
  }) async {
    if (_mockMediaSourceDir.isEmpty) {
      return null;
    }

    _mockMediaSequence += 1;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(":", "-")
        .replaceAll(".", "-");
    final destinationPath = await _getSessionMediaPath(
        "mock_${_mockMediaSequence}_$timestamp.$extension");
    for (final sourceFileName in sourceFileNames) {
      final source = File(_joinPath(_mockMediaSourceDir, sourceFileName));
      if (await source.exists()) {
        final destination = File(destinationPath);
        await destination.parent.create(recursive: true);
        await source.copy(destination.path);
        LogService.instance.registerLog(
            "Copied configured mock media from ${source.path} to $destinationPath");
        return destinationPath;
      }
    }

    throw Exception(
        "HYDRACAM_MOCK_MEDIA_SOURCE_DIR is set to $_mockMediaSourceDir, "
        "but none of ${sourceFileNames.join(", ")} exist.");
  }

  String _joinPath(String directoryPath, String fileName) {
    if (directoryPath.endsWith("/") || directoryPath.endsWith(r"\")) {
      return "$directoryPath$fileName";
    }
    return "$directoryPath${Platform.pathSeparator}$fileName";
  }

  /// Applies the selected exposure preset before recording starts. Failures
  /// never block recording: the clip falls back to auto exposure and the
  /// metadata records why.
  void _requireNoCaptureReconfiguration({bool duringRecordingStart = false}) {
    if (_isRecording ||
        _videoAttempt != null ||
        _cameraStopInFlight != null ||
        _recordingStopInFlight != null ||
        (!duringRecordingStart && _recordingStartInFlight != null)) {
      throw Exception(
          "Camera reconfiguration must wait for capture settlement");
    }
  }

  Future<void> _settleExposureBeforeReuse() async {
    if (_videoAttempt != null) {
      throw StateError(
          "Original recording has not reached terminal settlement");
    }
    await _hardwareClosing?.timeout(_cameraOperationTimeout);
    if (!_exposureOwnerWasDisposed ||
        !(_recordingExposure?.cleanupPending ?? false)) {
      await _abortRecordingExposure(requireReleased: true);
      return;
    }
    final inFlight = _exposureRecoveryInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    late final Future<void> recovering;
    recovering = _reactivateOriginalExposureOwner().whenComplete(() {
      if (identical(_exposureRecoveryInFlight, recovering)) {
        _exposureRecoveryInFlight = null;
      }
    });
    _exposureRecoveryInFlight = recovering;
    return recovering;
  }

  Future<void> _reactivateOriginalExposureOwner() async {
    final origin = _exposureCameraOrigin;
    if (origin == null) {
      throw Exception("Original exposure camera is unavailable for cleanup");
    }
    try {
      // Only the saved preview may reactivate the original native control.
      // No new exposure owner or encoder is created here.
      _controller = origin.explicitFps
          ? _createController(origin.camera, origin.profile)
          : _createControllerUsingPresetDefaults(origin.camera, origin.profile);
      _flashAvailable = null;
      await _controller!.initialize().timeout(_cameraOperationTimeout);
      _isCameraInitialized = true;
      await _abortRecordingExposure(requireReleased: true);
    } finally {
      // A timeout or control mismatch must close the recovery hardware too.
      // Retained ownership is cleared only by the original native ACK.
      await _disposeController("exposure owner recovery",
          allowUnsettledExposure: true);
    }
  }

  Future<void> _lockRecordingExposure() async {
    await _abortRecordingExposure(requireReleased: true);
    final cameraName = _controller?.description.name;
    if (cameraName == null) {
      return;
    }
    final preset = await SettingsService.getExposurePreset();
    final session = RecordingExposureSession(
      service: _manualExposureService,
      preset: preset,
      cameraName: cameraName,
      frameDurationNs: 1000000000 ~/ _currentProfile.framesPerSecond,
    );
    _recordingExposure = session;
    _exposureCameraOrigin = (
      camera: _controller!.description,
      profile: _currentProfile,
      explicitFps: _controllerUsesExplicitFps,
    );
    try {
      await session.lockBeforeStart().timeout(_cameraOperationTimeout);
      if (session.lockStatus == "busy" ||
          (!session.isLocked && session.cleanupPending)) {
        throw StateError("Exposure ownership is unresolved before recording");
      }
      LogService.instance.registerLog(
          "Exposure preset ${preset.storageValue}: ${session.lockStatus}");
    } catch (error) {
      LogService.instance.registerLog("Exposure lock failed: $error");
      if (session.cleanupPending) {
        rethrow;
      }
    }
  }

  Future<void> _abortRecordingExposure({bool requireReleased = false}) async {
    final session = _recordingExposure;
    try {
      if (session != null) {
        await session.abort().timeout(session.snapshotTimeout);
      }
    } catch (error) {
      LogService.instance.registerLog("Exposure release failed: $error");
    }
    if (session == null || !session.cleanupPending) {
      if (identical(_recordingExposure, session)) {
        _recordingExposure = null;
        _exposureCameraOrigin = null;
        _exposureOwnerWasDisposed = false;
      }
    } else if (requireReleased) {
      throw StateError("Exposure cleanup must finish before recording");
    }
  }

  Future<MediaCaptureContext> _buildCurrentCaptureContext() async {
    final profile = await SettingsService.getVideoCaptureProfile();
    return CameraSetupService.instance.buildCaptureContext(
      controller: _controller,
      videoCaptureProfile: profile.storageValue,
    );
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
    return _getMediaPathForSession(
        fileName, SessionManager.instance.sessionGuid);
  }

  Future<String> _getMediaPathForSession(
      String fileName, String? originalSessionGuid) async {
    final sessionGuid = originalSessionGuid?.trim();
    if (sessionGuid == null || sessionGuid.isEmpty) {
      throw Exception(
          "No active service session available for captured media.");
    }
    final directory = await getApplicationDocumentsDirectory();
    final sessionDir = Directory("${directory.path}/session_$sessionGuid");
    if (!sessionDir.existsSync()) {
      sessionDir.createSync(recursive: true);
    }
    return "${sessionDir.path}/$fileName";
  }
}

/// One application-owned dispatch. Controller, delegate and camera ID are
/// captured together; a later global camera can never receive this STOP.
class _OwnedVideoAttempt {
  _OwnedVideoAttempt({
    required this.controller,
    required this.platform,
    required this.cameraId,
    required this.captureId,
    required this.exposure,
    required MediaCaptureContext? context,
    required this.startedAt,
    required this.sessionGuid,
    required this.supportsPostDisposeStop,
  }) : context = RecordedVideoSnapshot.capture(
                captureId: captureId,
                path: "",
                startedAt: startedAt,
                stoppedAt: null,
                context: context)
            .context;

  final CameraController controller;
  final CameraPlatform platform;
  final int cameraId;
  final String captureId;
  final RecordingExposureSession? exposure;
  final DateTime startedAt;
  final String? sessionGuid;
  final bool supportsPostDisposeStop;
  late final Future<void> rawStart;
  Future<String>? settlement;
  MediaCaptureContext? context;
  DateTime? stoppedAt;
  bool disposed = false;
  bool terminal = false;
}
