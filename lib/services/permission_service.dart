import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'log_service.dart';

class PermissionService {
  /// Requests all required permissions and returns `true` if all are granted.
  static Future<bool> requestAllPermissions() async {
    // Add permissions based on the platform
    final permissions = <Permission>[
      Permission.camera,
      Permission.microphone,
      if (Platform.isAndroid && Platform.version.startsWith('11'))
        Permission.manageExternalStorage,
      if (Platform.isAndroid && !Platform.version.startsWith('11'))
        Permission.storage,
      if (Platform.isIOS) Permission.photos,
      Permission.location,
    ];

    // Request permissions
    final statuses = await permissions.request();

    // Separate permissions into granted and denied categories
    final grantedPermissions = statuses.entries
        .where((entry) => entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    final deniedPermissions = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    // Construct the log message
    final logMessage = 'Permission request completed.\n'
        'Granted: $grantedPermissions\n'
        'Denied: $deniedPermissions';

    // Log the permissions status
    LogService.instance.registerLog(
      logMessage,
      function: 'requestAllPermissions',
      file: 'PermissionService',
    );

    // Check if all permissions are granted
    return statuses.values.every((status) => status.isGranted);
  }

  /// Opens the app settings page.
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
