import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "log_service.dart";
import "../automation/automation_config.dart";

class LaunchConfig {
  const LaunchConfig({
    this.role,
    this.preferredMasterIp,
    this.targetId,
    this.forceSlaveMode = false,
  });

  final String? role;
  final String? preferredMasterIp;
  final String? targetId;
  final bool forceSlaveMode;

  bool get wantsMaster => role?.toLowerCase() == "master";
  bool get wantsSlave => role?.toLowerCase() == "slave";
  bool get wantsStandby => role?.toLowerCase() == "standby";
}

class LaunchConfigService {
  LaunchConfigService._();

  static final LaunchConfigService instance = LaunchConfigService._();
  static const MethodChannel _channel =
      MethodChannel("hydracamv2/launch_config");
  static const int _platformConfigAttempts = 20;
  static const Duration _platformConfigRetryDelay = Duration(milliseconds: 100);

  LaunchConfig? _cached;

  LaunchConfig? get config => _cached;

  Future<LaunchConfig?> load() async {
    if (!automationEnabled) {
      _cached = null;
      return null;
    }

    final prefs = await SharedPreferences.getInstance();

    final platformResult = await _loadPlatformLaunchConfig();
    if (platformResult != null && platformResult.isNotEmpty) {
      LogService.instance.registerLog(
          "Launch config from intent: role=${platformResult['role']}, "
          "preferredMasterIp=${platformResult['preferredMasterIp']}, "
          "targetId=${platformResult['automationTargetId']}, "
          "forceSlaveMode=${platformResult['forceSlaveMode']}");

      // Persist to SharedPreferences for future restarts
      await prefs.setString(
          "launch_role", platformResult["role"] as String? ?? "");
      await prefs.setString("launch_master_ip",
          platformResult["preferredMasterIp"] as String? ?? "");
      await prefs.setString("launch_automation_target_id",
          platformResult["automationTargetId"] as String? ?? "");
      await prefs.setBool("launch_force_slave",
          platformResult["forceSlaveMode"] as bool? ?? false);

      _cached = LaunchConfig(
        role: platformResult["role"] as String?,
        preferredMasterIp: platformResult["preferredMasterIp"] as String?,
        targetId: platformResult["automationTargetId"] as String?,
        forceSlaveMode: platformResult["forceSlaveMode"] as bool? ?? false,
      );
      return _cached;
    }

    if (automationRole.isNotEmpty ||
        automationPreferredMasterIp.isNotEmpty ||
        automationTargetId.isNotEmpty ||
        automationForceSlaveMode) {
      LogService.instance
          .registerLog("Launch config from Dart defines: role=$automationRole, "
              "preferredMasterIp=$automationPreferredMasterIp, "
              "targetId=$automationTargetId, "
              "forceSlaveMode=$automationForceSlaveMode");
      _cached = LaunchConfig(
        role: automationRole.isEmpty ? null : automationRole,
        preferredMasterIp: automationPreferredMasterIp.isEmpty
            ? null
            : automationPreferredMasterIp,
        targetId: automationTargetId.isEmpty ? null : automationTargetId,
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
              "targetId=${prefs.getString("launch_automation_target_id")}, "
              "forceSlaveMode=${prefs.getBool("launch_force_slave")}");

      _cached = LaunchConfig(
        role: savedRole,
        preferredMasterIp: prefs.getString("launch_master_ip"),
        targetId: prefs.getString("launch_automation_target_id"),
        forceSlaveMode: prefs.getBool("launch_force_slave") ?? false,
      );
      return _cached;
    }

    LogService.instance
        .registerLog("No launch config found in intent or SharedPreferences");
    _cached = null;
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlatformLaunchConfig() async {
    Object? lastMissingPluginError;
    for (var attempt = 0; attempt < _platformConfigAttempts; attempt++) {
      try {
        return await _channel.invokeMapMethod<String, dynamic>(
          "getLaunchConfig",
        );
      } on MissingPluginException catch (error) {
        lastMissingPluginError = error;
        await Future<void>.delayed(_platformConfigRetryDelay);
      } on PlatformException catch (error) {
        LogService.instance.registerLog(
            "Failed to load launch config from platform: ${error.message}");
        return null;
      } catch (error) {
        LogService.instance
            .registerLog("Failed to load launch config from platform: $error");
        return null;
      }
    }
    if (lastMissingPluginError != null) {
      LogService.instance
          .registerLog("Failed to load launch config from platform after "
              "$_platformConfigAttempts attempts: $lastMissingPluginError");
    }
    return null;
  }
}
