import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/runtime_role_switch.dart";
import "package:hydracam/services/launch_config_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  test("runtime role switch request parses standby", () {
    final request = RuntimeRoleSwitchRequest.fromPayload({
      "role": "standby",
    });

    expect(request.role, RuntimeAutomationRole.standby);
    expect(request.preferredMasterIp, isNull);
    expect(request.forceSlaveMode, isFalse);
    expect(request.toJson(), {
      "role": "standby",
      "preferredMasterIp": null,
      "forceSlaveMode": false,
    });
  });

  test("runtime role switch request forces slave with master IP", () {
    final request = RuntimeRoleSwitchRequest.fromPayload({
      "role": "slave",
      "preferredMasterIp": "192.168.178.153",
    });

    expect(request.role, RuntimeAutomationRole.slave);
    expect(request.preferredMasterIp, "192.168.178.153");
    expect(request.forceSlaveMode, isTrue);
  });

  test("launch config recognizes standby role", () {
    const config = LaunchConfig(role: "standby", targetId: "ipad");

    expect(config.wantsStandby, isTrue);
    expect(config.wantsMaster, isFalse);
    expect(config.wantsSlave, isFalse);
    expect(config.targetId, "ipad");
  });

  test("launch config recognizes setup preview role", () {
    const config = LaunchConfig(role: "setup", targetId: "android-tilted");

    expect(config.wantsSetupPreview, isTrue);
    expect(config.wantsStandby, isFalse);
    expect(config.wantsMaster, isFalse);
    expect(config.wantsSlave, isFalse);
    expect(config.targetId, "android-tilted");
  });

  test("launch config ignores stale saved automation role", () async {
    SharedPreferences.setMockInitialValues({
      "launch_role": "standby",
      "launch_master_ip": "192.168.178.153",
      "launch_automation_target_id": "s7",
      "launch_force_slave": true,
    });
    final service = LaunchConfigService.forTesting(
      automationEnabled: true,
      platformConfigLoader: () async => {},
    );

    final config = await service.load();

    expect(config, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString("launch_role"), isNull);
    expect(prefs.getString("launch_master_ip"), isNull);
    expect(prefs.getString("launch_automation_target_id"), isNull);
    expect(prefs.getBool("launch_force_slave"), isNull);
  });

  test("launch config uses fresh platform automation role", () async {
    SharedPreferences.setMockInitialValues({});
    final service = LaunchConfigService.forTesting(
      automationEnabled: true,
      platformConfigLoader: () async => {
        "role": "standby",
        "preferredMasterIp": "192.168.178.153",
        "automationTargetId": "s7",
        "forceSlaveMode": false,
      },
    );

    final config = await service.load();

    expect(config?.role, "standby");
    expect(config?.preferredMasterIp, "192.168.178.153");
    expect(config?.targetId, "s7");
    expect(config?.forceSlaveMode, isFalse);
  });

  test("launch config identifies a manual launcher start", () async {
    SharedPreferences.setMockInitialValues({});
    final service = LaunchConfigService.forTesting(
      automationEnabled: true,
      platformConfigLoader: () async => {
        "manualLaunch": true,
      },
    );

    final config = await service.load();

    expect(config?.isManualLaunch, isTrue);
    expect(config?.role, isNull);
    expect(config?.wantsStandby, isFalse);
    expect(config?.forceSlaveMode, isFalse);
  });

  test("launch config clear removes cached automation role", () async {
    SharedPreferences.setMockInitialValues({});
    final service = LaunchConfigService.forTesting(
      automationEnabled: true,
      platformConfigLoader: () async => {
        "role": "standby",
        "automationTargetId": "s7",
      },
    );

    await service.load();
    expect(service.config?.wantsStandby, isTrue);

    await service.clearSavedAutomationLaunchConfig();

    expect(service.config, isNull);
  });
}
