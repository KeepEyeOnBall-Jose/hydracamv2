import 'package:camera/camera.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'log_service.dart';

class CameraService {
  CameraController? _controller;
  CameraController? get controller => _controller;

  bool _isCameraInitialized = false; // Tracks camera initialization status

  DateTime? videoStartRecordingDate;
  DateTime? videoEndRecordingDate;

  Function(String)? onPhotoTaken; // Callback to notify SlaveScreen about photos
  Function(String)? onVideoRecorded; // Callback to notify SlaveScreen about videos

  // Constructor to include the callbacks
  CameraService({this.onPhotoTaken, this.onVideoRecorded});

  Future<void> startCamera() async {
    final cameras = await availableCameras();
    _controller = CameraController(cameras[0], ResolutionPreset.high);

    try {
      await _controller?.initialize();
      await _controller?.setFlashMode(FlashMode.off); // Ensure the flash is off at startup
      LogService.instance.registerLog("Camera initialized with flash off");
    } catch (e) {
      LogService.instance.registerLog("Error initializing camera: $e");
    }
  }

  /// Ensures the camera is ready before any operation
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

  Future<void> stopCamera() async {
    try {
      await _controller?.setFlashMode(FlashMode.off); // Turn off flash when stopping the camera
      await _controller?.dispose();
      LogService.instance.registerLog("Camera stopped");
    } catch (e) {
      LogService.instance.registerLog("Error stopping camera: $e");
    }
  }
}
