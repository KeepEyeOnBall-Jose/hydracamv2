// camera_service_factory.dart
/*
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'mobile_camera_service.dart';
import 'new_camera_service.dart';
import 'windows_camera_service.dart';

class CameraServiceFactory {
  static NewCameraService createCameraService({
    Function(String)? onPhotoTaken,
    Function(String)? onVideoRecorded,
  }) {
    if (kIsWeb) {
      throw UnsupportedError('Camera not supported on Web.');
    } else if (Platform.isWindows) {
      return WindowsCameraService();
    } else if (Platform.isAndroid || Platform.isIOS) {
      return MobileCameraService(onPhotoTaken: onPhotoTaken, onVideoRecorded: onVideoRecorded);
    } else {
      throw UnsupportedError('Camera not supported on this platform.');
    }
  }
}
*/