enum RuntimeAutomationRole {
  master("master"),
  slave("slave"),
  standby("standby");

  const RuntimeAutomationRole(this.storageValue);

  final String storageValue;

  static RuntimeAutomationRole fromString(String value) {
    final normalized = value.trim().toLowerCase();
    for (final role in RuntimeAutomationRole.values) {
      if (role.storageValue == normalized) {
        return role;
      }
    }
    throw ArgumentError.value(value, "role", "Unsupported runtime role");
  }
}

class RuntimeRoleSwitchRequest {
  const RuntimeRoleSwitchRequest({
    required this.role,
    this.preferredMasterIp,
    bool? forceSlaveMode,
  }) : forceSlaveMode = forceSlaveMode ?? role == RuntimeAutomationRole.slave;

  final RuntimeAutomationRole role;
  final String? preferredMasterIp;
  final bool forceSlaveMode;

  static RuntimeRoleSwitchRequest fromPayload(Map<String, dynamic> payload) {
    final roleValue = payload["role"];
    if (roleValue is! String || roleValue.trim().isEmpty) {
      throw const FormatException("role is required");
    }

    final preferredMasterIpValue = payload["preferredMasterIp"];
    final forceSlaveModeValue = payload["forceSlaveMode"];
    return RuntimeRoleSwitchRequest(
      role: RuntimeAutomationRole.fromString(roleValue),
      preferredMasterIp: preferredMasterIpValue is String &&
              preferredMasterIpValue.trim().isNotEmpty
          ? preferredMasterIpValue.trim()
          : null,
      forceSlaveMode: forceSlaveModeValue is bool ? forceSlaveModeValue : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "role": role.storageValue,
      "preferredMasterIp": preferredMasterIp,
      "forceSlaveMode": forceSlaveMode,
    };
  }
}
