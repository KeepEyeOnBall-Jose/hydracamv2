import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../globals.dart';
import 'log_service.dart';

/// LocationService - Manages location-related functionality in the app.
/// This service handles location permissions, retrieves the current location,
/// and provides utility methods to access and format the location data.
///
/// ### Responsibilities:
/// - Checks and requests location permissions from the user.
/// - Retrieves the current GPS location with the best available accuracy.
/// - Logs location-related operations for debugging and monitoring purposes.
/// - Provides a formatted string representation of the current location.
///
/// This service is implemented as a singleton to ensure consistent location data across the app.
class LocationService {

  /// The current GPS position.
  Position? _currentPosition;

  /// Singleton instance of the `LocationService`.
  static final LocationService _instance = LocationService._internal();

  /// Factory constructor to access the singleton instance.
  factory LocationService() {
    return _instance;
  }

  /// Private constructor for the singleton pattern.
  LocationService._internal();

  /// Initializes the location service by checking permissions and attempting to get the location.
  ///
  /// - Logs each step of the initialization process.
  /// - Requests location permissions if necessary.
  /// - Tries to obtain the current GPS location.
  Future<void> initialize() async {
    try {
      LogService.instance.registerLog("Checking and requesting permissions", file:"location_service.dart", function: "initialize");
      await _checkAndRequestPermissions();
      LogService.instance.registerLog("Attempt to Get Location", file:"location_service.dart", function: "initialize");
      await _attemptToGetLocation();
    } catch (e) {
      LogService.instance.registerLog("Error initializing location service: $e", file:"location_service.dart", function: "initialize");
    }

  }

  /// Checks and requests location permissions.
  ///
  /// - Prompts the user to enable location services if they are disabled.
  /// - Requests location permissions if they are not already granted.
  /// - Logs the status of permissions and location services.
  Future<void> _checkAndRequestPermissions() async {
    bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        LogService.instance.registerLog("Location services are disabled.");
        await Geolocator.openLocationSettings();
      }
    } catch (e) {
      LogService.instance.registerLog("Error checking or opening location settings: $e");
      serviceEnabled = false; // Assume disabled to proceed safely
    }


    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      LogService.instance.registerLog("Location permissions are permanently denied.");
    }
  }

  /// Attempts to get the current GPS location.
  ///
  /// - Uses `Geolocator.getCurrentPosition` to fetch the location with the best available accuracy.
  /// - Sets a timeout to prevent indefinite waiting in case of issues.
  /// - Updates the `_currentPosition` property with the retrieved location.
  /// - Logs the result or any errors encountered during the process.
  Future<void> _attemptToGetLocation() async {
    try {
      LogService.instance.registerLog("Try get location: $_currentPosition");
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      ).timeout(Duration(seconds: locationTimeout), onTimeout: () {
        LogService.instance.registerLog("Timeout obtaining location");
        throw TimeoutException("Timeout obtaining location");
      });
      LogService.instance.registerLog("Location obtained: $_currentPosition");
    } catch (e) {
      LogService.instance.registerLog("Error obtaining location: $e");
      _currentPosition = null; // Set as null to indicate failure
    }
  }

  /// Triggers an explicit update of the location.
  Future<void> updateLocation() async {
    LogService.instance.registerLog("Updating location...");
    await _checkAndRequestPermissions();
    await _attemptToGetLocation();
  }

  /// Gets the current position. Returns the last known position, or `null` if no location is available.
  Position? get currentPosition => _currentPosition;

  /// Provides a formatted string representation of the current GPS position.
  ///
  /// - Returns a human-readable string of latitude and longitude if the location is available.
  /// - Returns "Location not available" if the location is not set.
  String get formattedPosition {
    if (_currentPosition == null) {
      return "Location not available";
    }
    return "Latitude: ${_currentPosition!.latitude}, Longitude: ${_currentPosition!.longitude}";
  }
}
