import "camera_service.dart";
import "storage_service.dart";

/// CameraServiceSingleton - a singleton for CameraService.
/// Ensures we only have ONE camera resource for the entire app (per device).
class CameraServiceSingleton {
  static CameraService? _instance;

  /// Returns the CameraService instance.
  static CameraService get instance {
    if (_instance == null) throw Exception("CameraServiceSingleton not initialized");
    return _instance!;
  }

  /// Private constructor to prevent instantiation.
  CameraServiceSingleton._();

  /// Initializes the singleton with the given [storageService].
  static CameraService initialize(StorageService storageService) {
    _instance = CameraService(storageService: storageService);
    return _instance!;
  }
}
