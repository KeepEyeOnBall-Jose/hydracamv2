import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/automation_config.dart";

const int expectedAutomationPort = int.fromEnvironment(
  "HYDRACAM_TEST_EXPECTED_AUTOMATION_PORT",
  defaultValue: 4762,
);

const String expectedAutomationTargetId = String.fromEnvironment(
  "HYDRACAM_TEST_EXPECTED_AUTOMATION_TARGET_ID",
  defaultValue: "",
);

void main() {
  test("automation bridge port can be overridden with a dart define", () {
    expect(automationServerPort, expectedAutomationPort);
  });

  test("automation target id can be overridden with a dart define", () {
    expect(automationTargetId, expectedAutomationTargetId);
  });
}
