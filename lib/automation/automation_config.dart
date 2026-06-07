const bool automationEnabled = bool.fromEnvironment(
  "HYDRACAM_AUTOMATION",
  defaultValue: false,
);

const bool mockCameraEnabled = bool.fromEnvironment(
  "HYDRACAM_MOCK_CAMERA",
  defaultValue: false,
);

const String automationRole = String.fromEnvironment(
  "HYDRACAM_AUTOMATION_ROLE",
  defaultValue: "",
);

const String automationPreferredMasterIp = String.fromEnvironment(
  "HYDRACAM_AUTOMATION_MASTER_IP",
  defaultValue: "",
);

const bool automationForceSlaveMode = bool.fromEnvironment(
  "HYDRACAM_AUTOMATION_FORCE_SLAVE",
  defaultValue: false,
);

const int automationServerPort = int.fromEnvironment(
  "HYDRACAM_AUTOMATION_PORT",
  defaultValue: 4762,
);
