const bool automationEnabled = bool.fromEnvironment(
  "HYDRACAM_AUTOMATION",
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

const int automationServerPort = int.fromEnvironment(
  "HYDRACAM_AUTOMATION_PORT",
  defaultValue: 4762,
);
