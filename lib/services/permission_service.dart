import "package:permission_handler/permission_handler.dart";
import "package:permission_handler/permission_handler.dart"
    as permission_handler;
import "log_service.dart";

// ignore: avoid_classes_with_only_static_members
class PermissionService {
  /// Requests the permissions required for initial app use.
  static Future<bool> requestAllPermissions() async {
    final permissions = <Permission>[
      Permission.camera,
      Permission.microphone,
    ];

    final statuses = await permissions.request();
    final grantedPermissions = statuses.entries
        .where((entry) => entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    final deniedPermissions = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList();

    final logMessage = "Permission request completed.\n"
        "Granted: $grantedPermissions\n"
        "Denied: $deniedPermissions";

    LogService.instance.registerLog(
      logMessage,
      function: "requestAllPermissions",
      file: "PermissionService",
    );

    return statuses.values.every((status) => status.isGranted);
  }

  /// Opens the app settings page.
  static Future<void> openAppSettings() async {
    await permission_handler.openAppSettings();
  }
}
