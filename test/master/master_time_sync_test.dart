import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

import "package:hydracam/master/master_server.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test("master timeSyncResponse uses the injected master clock", () async {
    final clockStamps = <DateTime>[
      DateTime.utc(2026, 6, 18, 15, 30, 0, 123),
      DateTime.utc(2026, 6, 18, 15, 30, 0, 456),
    ];
    final server = MasterServer(
      MockCameraService(),
      now: () => clockStamps.removeAt(0),
    );
    final socket = MockWebSocket();

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "timeSyncRequest",
        "deviceId": "slave-deterministic",
        "id": "7:2",
        "t0": "2026-06-18T15:29:59.900Z",
      }),
      socket: socket,
    );

    final sent =
        verify(() => socket.add(captureAny())).captured.single as String;
    final decoded = jsonDecode(sent) as Map<String, dynamic>;

    expect(decoded["type"], "timeSyncResponse");
    expect(decoded["id"], "7:2");
    expect(decoded["t0"], "2026-06-18T15:29:59.900Z");
    expect(decoded["t1"], "2026-06-18T15:30:00.123Z");
    expect(decoded["t2"], "2026-06-18T15:30:00.456Z");
    expect(clockStamps, isEmpty);
  });
}
