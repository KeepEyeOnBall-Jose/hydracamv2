import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "log_service.dart";
import "../automation/automation_config.dart";

typedef PlatformLaunchConfigLoader = Future<Map<String, dynamic>?> Function();

class LaunchConfig {
  const LaunchConfig({
    this.role,
    this.preferredMasterIp,
    this.targetId,
    this.forceSlaveMode = false,
    this.isManualLaunch = false,
  });

  final String? role;
  final String? preferredMasterIp;
  final String? targetId;
  final bool forceSlaveMode;
  final bool isManualLaunch;

  bool get wantsMaster => role?.toLowerCase() == "master";
  bool get wantsSlave => role?.toLowerCase() == "slave";
  bool get wantsStandby => role?.toLowerCase() == "standby";
  bool get wantsSetupPreview => role?.toLowerCase() == "setup";
}

class LaunchConfigService {
  LaunchConfigService._({
    bool? automationEnabledOverride,
    PlatformLaunchConfigLoader? platformConfigLoader,
  })  : _automationEnabled = automationEnabledOverride ?? automationEnabled,
        _platformConfigLoader = platformConfigLoader;

  factory LaunchConfigService.forTesting({
    required bool automationEnabled,
    required PlatformLaunchConfigLoader platformConfigLoader,
  }) {
    return LaunchConfigService._(
      automationEnabledOverride: automationEnabled,
      platformConfigLoader: platformConfigLoader,
    );
  }

  static final LaunchConfigService instance = LaunchConfigService._();
  static const MethodChannel _channel =
      MethodChannel("hydracamv2/launch_config");
  static const int _platformConfigAttempts = 20;
  static const Duration _platformConfigRetryDelay = Duration(milliseconds: 100);
  static const String _launchRoleKey = "launch_role";
  static const String _launchMasterIpKey = "launch_master_ip";
  static const String _launchAutomationTargetIdKey =
      "launch_automation_target_id";
  static const String _launchForceSlaveKey = "launch_force_slave";

  final bool _automationEnabled;
  final PlatformLaunchConfigLoader? _platformConfigLoader;
  LaunchConfig? _cached;

  LaunchConfig? get config => _cached;

  Future<LaunchConfig?> load() async {
    if (!_automationEnabled) {
      _cached = null;
      return null;
    }

    final platformResult = await _loadPlatformLaunchConfigWithOverride();
    if (platformResult != null && platformResult.isNotEmpty) {
      LogService.instance.registerLog(
          "Launch config from intent: role=${platformResult['role']}, "
          "preferredMasterIp=${platformResult['preferredMasterIp']}, "
          "targetId=${platformResult['automationTargetId']}, "
          "forceSlaveMode=${platformResult['forceSlaveMode']}, "
          "manualLaunch=${platformResult['manualLaunch']}");

      await clearSavedAutomationLaunchConfig();

      _cached = LaunchConfig(
        role: platformResult["role"] as String?,
        preferredMasterIp: platformResult["preferredMasterIp"] as String?,
        targetId: platformResult["automationTargetId"] as String?,
        forceSlaveMode: platformResult["forceSlaveMode"] as bool? ?? false,
        isManualLaunch: platformResult["manualLaunch"] as bool? ?? false,
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

    await clearSavedAutomationLaunchConfig();
    LogService.instance.registerLog("No fresh launch config found.");
    _cached = null;
    return null;
  }

  Future<void> clearSavedAutomationLaunchConfig() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_launchRoleKey);
    await prefs.remove(_launchMasterIpKey);
    await prefs.remove(_launchAutomationTargetIdKey);
    await prefs.remove(_launchForceSlaveKey);
  }

  Future<Map<String, dynamic>?> _loadPlatformLaunchConfigWithOverride() {
    final loader = _platformConfigLoader;
    if (loader != null) {
      return loader();
    }
    return _loadPlatformLaunchConfig();
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
