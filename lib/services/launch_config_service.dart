import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "log_service.dart";
import "../automation/automation_config.dart";

class LaunchConfig {
  const LaunchConfig({
    this.role,
    this.preferredMasterIp,
    this.forceSlaveMode = false,
  });

  final String? role;
  final String? preferredMasterIp;
  final bool forceSlaveMode;

  bool get wantsMaster => role?.toLowerCase() == "master";
  bool get wantsSlave => role?.toLowerCase() == "slave";
}

class LaunchConfigService {
  LaunchConfigService._();

  static final LaunchConfigService instance = LaunchConfigService._();
  static const MethodChannel _channel =
      MethodChannel("hydracamv2/launch_config");

  LaunchConfig? _cached;

  LaunchConfig? get config => _cached;

  Future<LaunchConfig?> load() async {
    if (!automationEnabled) {
      _cached = null;
      return null;
    }

    final prefs = await SharedPreferences.getInstance();

    // Try to load from platform channel first (fresh intent extras)
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>("getLaunchConfig");
      if (result != null && result.isNotEmpty) {
        LogService.instance
            .registerLog("Launch config from intent: role=${result['role']}, "
                "preferredMasterIp=${result['preferredMasterIp']}, "
                "forceSlaveMode=${result['forceSlaveMode']}");

        // Persist to SharedPreferences for future restarts
        await prefs.setString("launch_role", result["role"] as String? ?? "");
        await prefs.setString(
            "launch_master_ip", result["preferredMasterIp"] as String? ?? "");
        await prefs.setBool(
            "launch_force_slave", result["forceSlaveMode"] as bool? ?? false);

        _cached = LaunchConfig(
          role: result["role"] as String?,
          preferredMasterIp: result["preferredMasterIp"] as String?,
          forceSlaveMode: result["forceSlaveMode"] as bool? ?? false,
        );
        return _cached;
      }
    } on PlatformException catch (error) {
      LogService.instance.registerLog(
          "Failed to load launch config from platform: ${error.message}");
    } catch (error) {
      LogService.instance
          .registerLog("Failed to load launch config from platform: $error");
    }

    if (automationRole.isNotEmpty ||
        automationPreferredMasterIp.isNotEmpty ||
        automationForceSlaveMode) {
      LogService.instance
          .registerLog("Launch config from Dart defines: role=$automationRole, "
              "preferredMasterIp=$automationPreferredMasterIp, "
              "forceSlaveMode=$automationForceSlaveMode");
      _cached = LaunchConfig(
        role: automationRole.isEmpty ? null : automationRole,
        preferredMasterIp: automationPreferredMasterIp.isEmpty
            ? null
            : automationPreferredMasterIp,
        forceSlaveMode: automationForceSlaveMode,
      );
      return _cached;
    }

    // Fallback: load from SharedPreferences (persisted from previous launch)
    final savedRole = prefs.getString("launch_role");
    if (savedRole != null && savedRole.isNotEmpty) {
      LogService.instance
          .registerLog("Launch config from SharedPreferences: role=$savedRole, "
              "preferredMasterIp=${prefs.getString("launch_master_ip")}, "
              "forceSlaveMode=${prefs.getBool("launch_force_slave")}");

      _cached = LaunchConfig(
        role: savedRole,
        preferredMasterIp: prefs.getString("launch_master_ip"),
        forceSlaveMode: prefs.getBool("launch_force_slave") ?? false,
      );
      return _cached;
    }

    LogService.instance
        .registerLog("No launch config found in intent or SharedPreferences");
    _cached = null;
    return null;
  }
}
