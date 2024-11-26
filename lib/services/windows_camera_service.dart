/*import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../constants.dart';
import 'log_service.dart';
import 'new_camera_service.dart';

/// WindowsCameraService - Manages camera operations for Windows using the `flutter_webrtc` plugin.
class WindowsCameraService implements NewCameraService {
  MediaStream? _localStream;
  final _mediaDevices = navigator.mediaDevices;

  List<MediaDeviceInfo> _availableCameras = []; // List of available cameras
  int _selectedCameraIndex = 0; // Index of the selected camera
  String? _selectedCameraId; // ID of the selected camera

  // Current camera quality setting (default: high)
  CameraQuality _currentQuality = CameraQuality.high;
  @override
  CameraQuality get currentQuality => _currentQuality;

  Function(String)? onPhotoTaken; // Callbacks (if needed)
  Function(String)? onVideoRecorded;

  /// Getter for accessing the local stream (controller equivalent).
  @override
  MediaStream? get controller => _localStream;

  /// Initializes the available cameras and selects the default camera.
  @override
  Future<void> initializeCameras() async {
    try {
      final devices = await _mediaDevices.enumerateDevices();
      _availableCameras = devices.where((d) => d.kind == 'videoinput').toList();

      if (_availableCameras.isEmpty) {
        LogService.instance.registerLog("No cameras available on this device.");
        return;
      }

      _selectedCameraIndex = 0; // Default to the first camera
      _selectedCameraId = _availableCameras[_selectedCameraIndex].deviceId;
    } catch (e) {
      LogService.instance.registerLog("Error initializing cameras: $e");
    }
  }

  /// Returns a list of available cameras.
  @override
  List<MediaDeviceInfo> getAvailableCameras() {
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
    _selectedCameraId = _availableCameras[_selectedCameraIndex].deviceId;

    // Restart the camera with the new selection
    await startCamera();
  }

  /// Starts the camera and initializes it with default settings.
  @override
  Future<void> startCamera() async {
    // Stop any existing stream
    await stopCamera();

    final constraints = <String, dynamic>{
      'audio': false,
      'video': {
        'deviceId': _selectedCameraId,
        'width': _getWidthForQuality(_currentQuality),
        'height': _getHeightForQuality(_currentQuality),
      },
    };

    try {
      _localStream = await _mediaDevices.getUserMedia(constraints);
      LogService.instance.registerLog("Camera initialized with constraints: $constraints");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
    }
  }

  /// Stops the camera and disposes of its resources.
  @override
  Future<void> stopCamera() async {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream = null;
      LogService.instance.registerLog("Camera stopped");
    }
  }

  /// Captures a photo (Not directly supported in flutter_webrtc).
  @override
  Future<String> takePhoto({bool enableFlash = false}) async {
    LogService.instance.registerLog("takePhoto not implemented for WindowsCameraService.");
    return "Feature not supported";
  }

  /// Starts recording a video (Not directly supported in flutter_webrtc).
  @override
  Future<void> startRecordingVideo({bool enableFlash = false}) async {
    LogService.instance.registerLog("startRecordingVideo not implemented for WindowsCameraService.");
  }

  /// Stops recording a video (Not directly supported in flutter_webrtc).
  @override
  Future<String> stopRecordingVideo() async {
    LogService.instance.registerLog("stopRecordingVideo not implemented for WindowsCameraService.");
    return "Feature not supported";
  }

  /// Sets the camera quality and reinitializes the controller.
  @override
  Future<void> setCameraQuality(CameraQuality quality) async {
    LogService.instance.registerLog("Changing camera quality to $quality (current: $_currentQuality)");
    _currentQuality = quality;

    // Restart the camera with the new quality
    await startCamera();
  }

  int _getWidthForQuality(CameraQuality quality) {
    switch (quality) {
      case CameraQuality.low:
        return 640;
      case CameraQuality.medium:
        return 1280;
      case CameraQuality.high:
      default:
        return 1920;
    }
  }

  int _getHeightForQuality(CameraQuality quality) {
    switch (quality) {
      case CameraQuality.low:
        return 480;
      case CameraQuality.medium:
        return 720;
      case CameraQuality.high:
      default:
        return 1080;
    }
  }
}*/
