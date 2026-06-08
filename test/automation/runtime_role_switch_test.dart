import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/runtime_role_switch.dart";
import "package:hydracam/services/launch_config_service.dart";

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
}
