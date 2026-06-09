import "package:flutter/foundation.dart";
import "package:permission_handler/permission_handler.dart"
    as permission_handler;
import "log_service.dart";

typedef PermissionRequester
    = Future<Map<permission_handler.Permission,
        permission_handler.PermissionStatus>> Function(
      List<permission_handler.Permission> permissions,
    );

// ignore: avoid_classes_with_only_static_members
class PermissionService {
  static PermissionRequester _requestPermissions = _defaultRequestPermissions;

  /// Requests the permissions required for initial app use.
  static Future<bool> requestAllPermissions() async {
    if (_usesNativeResourcePrompts) {
      LogService.instance.registerLog(
        "Skipping permission_handler startup request on ${defaultTargetPlatform.name}; "
        "native platform APIs will request resource access on demand.",
        function: "requestAllPermissions",
        file: "PermissionService",
      );
      return true;
    }

    final permissions = _startupPermissionsFor(defaultTargetPlatform);

    final statuses = await _requestPermissions(permissions);
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

  static List<permission_handler.Permission> _startupPermissionsFor(
    TargetPlatform platform,
  ) {
    return [
      permission_handler.Permission.camera,
      permission_handler.Permission.microphone,
      if (platform == TargetPlatform.android)
        permission_handler.Permission.locationWhenInUse,
    ];
  }

  static Future<
      Map<permission_handler.Permission,
          permission_handler.PermissionStatus>> _defaultRequestPermissions(
    List<permission_handler.Permission> permissions,
  ) {
    return permissions.request();
  }

  @visibleForTesting
  static void configurePermissionRequesterForTesting(
    PermissionRequester requester,
  ) {
    _requestPermissions = requester;
  }

  @visibleForTesting
  static void resetPermissionRequesterForTesting() {
    _requestPermissions = _defaultRequestPermissions;
  }

  static bool get _usesNativeResourcePrompts =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Opens the app settings page.
  static Future<void> openAppSettings() async {
    if (_usesNativeResourcePrompts) {
      LogService.instance.registerLog(
        "Skipping permission_handler openAppSettings on ${defaultTargetPlatform.name}.",
        function: "openAppSettings",
        file: "PermissionService",
      );
      return;
    }

    await permission_handler.openAppSettings();
  }
}
