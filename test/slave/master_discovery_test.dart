import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/slave/master_discovery.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    LogService.instance.clearLogs();
  });

  test("startListening is idempotent while discovery socket is active",
      () async {
    final discovery = MasterDiscovery(onMasterDiscovered: (_) {});

    await discovery.startListening();
    await discovery.startListening();
    await discovery.stopListening();

    final messages =
        LogService.instance.logs.map((entry) => entry["message"]).toList();

    expect(
      messages.where(
        (message) =>
            message ==
            "Listening for master broadcast on port ${MasterDiscovery.broadcastPort}...",
      ),
      hasLength(1),
    );
    expect(messages, contains("MasterDiscovery is already listening."));
  });

  test("stopListening allows discovery to start again", () async {
    final discovery = MasterDiscovery(onMasterDiscovered: (_) {});

    await discovery.startListening();
    await discovery.stopListening();
    await discovery.startListening();
    await discovery.stopListening();

    final messages =
        LogService.instance.logs.map((entry) => entry["message"]).toList();

    expect(
      messages.where(
        (message) =>
            message ==
            "Listening for master broadcast on port ${MasterDiscovery.broadcastPort}...",
      ),
      hasLength(2),
    );
    expect(
      messages.where(
        (message) => message == "Stopped listening for master broadcast.",
      ),
      hasLength(2),
    );
  });
}
