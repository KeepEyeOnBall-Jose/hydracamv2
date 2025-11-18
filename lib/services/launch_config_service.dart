import "package:flutter/services.dart";

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

    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>("getLaunchConfig");
      if (result == null || result.isEmpty) {
        _cached = null;
        return null;
      }
      _cached = LaunchConfig(
        role: result["role"] as String?,
        preferredMasterIp: result["preferredMasterIp"] as String?,
        forceSlaveMode: result["forceSlaveMode"] as bool? ?? false,
      );
      return _cached;
    } on PlatformException catch (error) {
      LogService.instance
          .registerLog("Failed to load launch config: ${error.message}");
    } catch (error) {
      LogService.instance.registerLog("Failed to load launch config: $error");
    }
    _cached = null;
    return null;
  }
}
