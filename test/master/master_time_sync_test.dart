import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

import "package:hydracam/master/master_server.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

void main() {
  test("master answers a timeSyncRequest with echoed id/t0 and its t1/t2",
      () async {
    final server = MasterServer(MockCameraService());
    final socket = MockWebSocket();

    final before = DateTime.now().toUtc();
    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "timeSyncRequest",
        "deviceId": "slave-a",
        "id": "3:5",
        "t0": "2026-01-01T00:00:00.000Z",
      }),
      socket: socket,
    );
    final after = DateTime.now().toUtc();

    final sent =
        verify(() => socket.add(captureAny())).captured.single as String;
    final decoded = jsonDecode(sent) as Map<String, dynamic>;

    expect(decoded["type"], "timeSyncResponse");
    expect(decoded["id"], "3:5");
    expect(decoded["t0"], "2026-01-01T00:00:00.000Z");

    final t1 = DateTime.parse(decoded["t1"] as String);
    final t2 = DateTime.parse(decoded["t2"] as String);
    // Both stamps are taken on the master between message receipt and reply.
    expect(t1.isBefore(before), isFalse);
    expect(t2.isAfter(after), isFalse);
    expect(t2.isBefore(t1), isFalse);
  });
}
