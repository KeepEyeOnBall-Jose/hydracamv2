import 'package:hydracam/services/camera_service.dart';

/// CameraServiceSingleton - a global singleton wrapper for CameraService.
/// Ensures we only have ONE camera resource for the entire app (per device).
class CameraServiceSingleton {
  // Private constructor prevents direct instantiation.
  CameraServiceSingleton._();

  // A single, lazily-initialized instance of CameraService.
  static final CameraService _instance = CameraService();

  /// Returns the global (singleton) CameraService instance.
  static CameraService get instance => _instance;
}
