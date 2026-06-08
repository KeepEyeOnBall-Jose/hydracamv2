import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "../app_theme.dart";
import "../screens/camera_selection_screen.dart";
import "../screens/login_screen.dart";
import "../screens/settings_screen.dart";
import "../screens/log_screen.dart";
import "../screens/uploader_info_screen.dart";
import "../services/alert_utils.dart";
import "../services/user_service.dart";

class HydraCamAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onBack;
  final List<Widget>? additionalActions; // For additional actions

  const HydraCamAppBar({
    super.key,
    required this.title,
    required this.onBack,
    this.additionalActions,
  });

  Future<void> _showAppVersionDialog(BuildContext context) async {
    // Obtain package information
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;

    // Show a dialog with version info
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("App Version"),
          content: Text("Version: $version\nBuild: $buildNumber"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final appBarWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.maybeSizeOf(context)?.width;
        final canShowActions = appBarWidth == null || appBarWidth >= 320;

        return AppBar(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          actions: [
            if (canShowActions && additionalActions != null)
              ...additionalActions!,
            if (canShowActions)
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                onSelected: (value) {
                  if (value == "Device Info") {
                    // Show info about device
                    AlertUtils.showDeviceInfoDialog(context);
                  } else if (value == "Settings") {
                    // Navigate to settings
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()),
                    );
                  } else if (value == "Location Info") {
                    // Show info about location
                    AlertUtils.showLocationInfoDialog(context);
                  } else if (value == "Logs") {
                    // Navigate to logs
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LogScreen()),
                    );
                  } else if (value == "Uploader Info") {
                    // Navigate to uploader info screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const UploaderInfoScreen()),
                    );
                  } else if (value == "Login") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  } else if (value == "App Version") {
                    _showAppVersionDialog(context); // Show app version dialog
                  } else if (value == "Camera Selection") {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CameraSelectionScreen()),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: "Device Info",
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Device Info"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "Settings",
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Settings"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "Camera Selection",
                    child: Row(
                      children: [
                        Icon(Icons.camera_alt, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Camera Selection"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "Location Info",
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Location Info"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "Logs",
                    child: Row(
                      children: [
                        Icon(Icons.list_alt, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Logs"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "Uploader Info",
                    child: Row(
                      children: [
                        Icon(Icons.cloud_upload, color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("Uploader Info"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: "App Version",
                    child: Row(
                      children: [
                        Icon(Icons.perm_device_info,
                            color: AppTheme.accentColor),
                        SizedBox(width: 8),
                        Text("App Version"),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: "Login",
                    child: Row(
                      children: [
                        Icon(
                            UserService().isLoggedIn
                                ? Icons.account_circle
                                : Icons.login,
                            color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text("Login"),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
