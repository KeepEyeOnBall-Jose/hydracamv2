import "package:flutter_test/flutter_test.dart";
import "package:hydracam/automation/automation_bridge.dart";

void main() {
  test("health snapshot exposes automation target identity", () {
    final health = AutomationBridge.instance.buildHealthSnapshot();

    expect(health["status"], "ok");
    expect(health["automation"], isTrue);
    expect(health, contains("automationTargetId"));
  });

  test("stale automation handler unregister does not remove current handler",
      () {
    final bridge = AutomationBridge.instance;
    final command = "race_test_${DateTime.now().microsecondsSinceEpoch}";

    Future<Map<String, dynamic>> staleHandler(
        Map<String, dynamic> payload) async {
      return {"handler": "stale"};
    }

    Future<Map<String, dynamic>> currentHandler(
        Map<String, dynamic> payload) async {
      return {"handler": "current"};
    }

    addTearDown(() {
      bridge.unregisterCommands([command]);
    });

    bridge.registerCommand(command, staleHandler);
    bridge.registerCommand(command, currentHandler);

    bridge.unregisterCommandsIfCurrent({command: staleHandler});

    expect(bridge.isCommandRegistered(command), isTrue);

    bridge.unregisterCommandsIfCurrent({command: currentHandler});

    expect(bridge.isCommandRegistered(command), isFalse);
  });
}
