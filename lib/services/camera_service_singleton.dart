import "package:flutter/foundation.dart";

import "camera_service.dart";
import "storage_service.dart";

/// CameraServiceSingleton - a singleton for CameraService.
/// Ensures we only have ONE camera resource for the entire app (per device).
class CameraServiceSingleton {
  static CameraService? _instance;

  /// Returns the CameraService instance.
  static CameraService get instance {
    if (_instance == null) {
      throw Exception("CameraServiceSingleton not initialized");
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  /// Private constructor to prevent instantiation.
  CameraServiceSingleton._();

  /// Initializes the singleton with the given [storageService].
  static CameraService initialize(
    StorageService storageService, {
    bool? useMockCamera,
  }) {
    _instance = CameraService(
      storageService: storageService,
      useMockCamera: useMockCamera,
    );
    return _instance!;
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }
}
