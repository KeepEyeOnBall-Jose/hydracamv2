/// A SERVICE THAT MANAGES ALL REQUIRED PERMISSIONS

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Requests all required permissions and returns `true` if all are granted.
  static Future<bool> requestAllPermissions() async {
    // Permissions required for the app
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
      Permission.photos, // For iOS photo access
      Permission.location,
      Permission.microphone, // If videos require audio
    ].request();

    // Check if all permissions are granted
    bool allGranted = statuses.values.every((status) => status.isGranted);

    return allGranted;
  }

  /// Checks if all required permissions are granted.
  static Future<bool> checkPermissions() async {
    return await Permission.camera.isGranted &&
        await Permission.storage.isGranted &&
        await Permission.photos.isGranted &&
        await Permission.location.isGranted &&
        await Permission.microphone.isGranted;
  }

  /// Requests a specific permission and returns its status.
  static Future<bool> requestPermission(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  /// Opens the app settings for the user to manually grant permissions.
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
