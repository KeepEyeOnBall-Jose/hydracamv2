import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("slave registers before waiting for network payload", () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
    });
    if (!CameraServiceSingleton.isInitialized) {
      final storageService = StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      );
      CameraServiceSingleton.initialize(
        storageService,
        useMockCamera: true,
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = StreamController<Map<String, dynamic>>.broadcast();
    final networkPayload = Completer<Map<String, dynamic>?>();
    final sockets = <WebSocket>[];

    server.listen((request) async {
      if (request.uri.path != "/ws") {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((data) {
        final decoded = jsonDecode(data as String);
        if (decoded is Map<String, dynamic>) {
          messages.add(decoded);
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () => networkPayload.future,
    );

    try {
      await client.connect();
      final first = await messages.stream.first.timeout(
        const Duration(milliseconds: 200),
      );

      expect(first["type"], "deviceId");
      expect(first["deviceId"], "test-device");
      expect(first.containsKey("network"), isFalse);

      networkPayload.complete({
        "isWifiActive": true,
        "ipAddress": "192.168.178.64",
        "source": "test",
      });
      final deferred = await messages.stream
          .firstWhere((message) => message["type"] == "heartbeat")
          .timeout(const Duration(seconds: 1));

      expect(deferred["deviceId"], "test-device");
      expect(deferred["network"], {
        "isWifiActive": true,
        "ipAddress": "192.168.178.64",
        "source": "test",
      });
    } finally {
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
      if (!networkPayload.isCompleted) {
        networkPayload.complete(null);
      }
    }
  });
}
