import 'package:geolocator/geolocator.dart';

import 'log_service.dart';

/// LocationService - Handles obtaining the device's current location.
/// Provides methods to get the current position and to access the last known location.
class LocationService {
  Position? _currentPosition;

  /// Singleton pattern
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  /// Initializes the location service and obtains the current position.
  Future<void> initialize() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      LogService.instance.registerLog("Location services are disabled.");
      return;
    }

    // Check for permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        LogService.instance.registerLog("Location permissions are denied.");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      LogService.instance.registerLog("Location permissions are permanently denied.");
      return;
    }

    // When permissions are granted, get the position
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      LogService.instance.registerLog("Current position: $_currentPosition");
    } catch (e) {
      LogService.instance.registerLog("Error obtaining location: $e");
    }
  }

  /// Returns the current position obtained during initialization.
  Position? get currentPosition => _currentPosition;

  /// Returns a formatted string of the current position.
  String get formattedPosition {
    if (_currentPosition == null) {
      return "Location not available";
    }
    return "Latitude: ${_currentPosition!.latitude}, Longitude: ${_currentPosition!.longitude}";
  }
}
