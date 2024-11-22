import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../globals.dart';
import 'log_service.dart';

class LocationService {
  Position? _currentPosition;

  /// Singleton pattern
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  /// Initializes the location service and attempts to get the location.
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

  /// Checks permissions and prompts the user to enable location services if needed.
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

  /// Tries to get the current location and updates the current position.
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

  /// Returns the current position.
  Position? get currentPosition => _currentPosition;

  /// Returns a formatted string of the current position.
  String get formattedPosition {
    if (_currentPosition == null) {
      return "Location not available";
    }
    return "Latitude: ${_currentPosition!.latitude}, Longitude: ${_currentPosition!.longitude}";
  }
}
