const bool automationEnabled = bool.fromEnvironment(
  "HYDRACAM_AUTOMATION",
  defaultValue: false,
);

const int automationServerPort = 4762;
