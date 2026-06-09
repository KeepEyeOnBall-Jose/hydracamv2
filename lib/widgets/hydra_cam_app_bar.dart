import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "../app_theme.dart";
import "../l10n/app_localizations.dart";
import "../l10n/app_localizations_en.dart";
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

  static const String _deviceInfoMenuValue = "deviceInfo";
  static const String _settingsMenuValue = "settings";
  static const String _cameraSelectionMenuValue = "cameraSelection";
  static const String _locationInfoMenuValue = "locationInfo";
  static const String _logsMenuValue = "logs";
  static const String _uploaderInfoMenuValue = "uploaderInfo";
  static const String _appVersionMenuValue = "appVersion";
  static const String _loginMenuValue = "login";

  const HydraCamAppBar({
    super.key,
    required this.title,
    required this.onBack,
    this.additionalActions,
  });

  AppLocalizations _localizationsFor(BuildContext context) {
    return Localizations.of<AppLocalizations>(
          context,
          AppLocalizations,
        ) ??
        AppLocalizationsEn();
  }

  Future<void> _showAppVersionDialog(BuildContext context) async {
    // Obtain package information
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    final buildNumber = packageInfo.buildNumber;

    // Show a dialog with version info
    if (context.mounted) {
      final l10n = _localizationsFor(context);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.appShellAppVersion),
          content: Text(l10n.appVersionDialogContent(
            version,
            buildNumber,
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.dialogOk),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _localizationsFor(context);

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
                  if (value == _deviceInfoMenuValue) {
                    // Show info about device
                    AlertUtils.showDeviceInfoDialog(context);
                  } else if (value == _settingsMenuValue) {
                    // Navigate to settings
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()),
                    );
                  } else if (value == _locationInfoMenuValue) {
                    // Show info about location
                    AlertUtils.showLocationInfoDialog(context);
                  } else if (value == _logsMenuValue) {
                    // Navigate to logs
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LogScreen()),
                    );
                  } else if (value == _uploaderInfoMenuValue) {
                    // Navigate to uploader info screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const UploaderInfoScreen()),
                    );
                  } else if (value == _loginMenuValue) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  } else if (value == _appVersionMenuValue) {
                    _showAppVersionDialog(context); // Show app version dialog
                  } else if (value == _cameraSelectionMenuValue) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CameraSelectionScreen()),
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _deviceInfoMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellDeviceInfo),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _settingsMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.settings,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellSettings),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _cameraSelectionMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.camera_alt,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellCameraSelection),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _locationInfoMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellLocationInfo),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _logsMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.list_alt,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellLogs),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _uploaderInfoMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_upload,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellUploaderInfo),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _appVersionMenuValue,
                    child: Row(
                      children: [
                        const Icon(Icons.perm_device_info,
                            color: AppTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(l10n.appShellAppVersion),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _loginMenuValue,
                    child: Row(
                      children: [
                        Icon(
                            UserService().isLoggedIn
                                ? Icons.account_circle
                                : Icons.login,
                            color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(l10n.appShellLogin),
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
