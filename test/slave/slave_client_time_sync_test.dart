import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/scheduled_task_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/services/time_sync_service.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({"device_id": "test-device"});
    if (!CameraServiceSingleton.isInitialized) {
      final storageService = StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      );
      CameraServiceSingleton.initialize(storageService, useMockCamera: true);
    }
    TimeSyncService.instance.reset();
  });
  tearDown(() => TimeSyncService.instance.reset());

  test("slave calibrates its clock from the master's timeSyncResponse replies",
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
        if (decoded is Map<String, dynamic> &&
            decoded["type"] == "timeSyncRequest") {
          // Reply like the real master: stamp receive/send time on reply.
          final now = DateTime.now().toUtc().toIso8601String();
          socket.add(jsonEncode({
            "type": "timeSyncResponse",
            "id": decoded["id"],
            "t0": decoded["t0"],
            "t1": now,
            "t2": now,
          }));
        }
      });
    });

    final scheduledTaskService = ScheduledTaskService();
    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      scheduledTaskService: scheduledTaskService,
    );

    final calibrated = Completer<TimeSyncResult>();
    void listener() {
      final value = TimeSyncService.instance.latest.value;
      if (value != null && !calibrated.isCompleted) {
        calibrated.complete(value);
      }
    }

    TimeSyncService.instance.latest.addListener(listener);

    try {
      await client.connect();
      final result = await calibrated.future.timeout(
        const Duration(seconds: 5),
      );

      expect(result.sampleCount, greaterThan(0));
      // Both ends share the test machine clock, so the offset is tiny.
      expect(result.offset.inMilliseconds.abs(), lessThan(2000));
      // The measured calibration is applied to the scheduling clock.
      expect(scheduledTaskService.clockOffset, result.offset);
    } finally {
      TimeSyncService.instance.latest.removeListener(listener);
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });

  test("malformed timeSyncResponse does not consume a pending sample",
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    String? firstProbeId;

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
        if (decoded is! Map<String, dynamic> ||
            decoded["type"] != "timeSyncRequest") {
          return;
        }

        final id = decoded["id"]?.toString();
        if (id == null || !id.endsWith(":0") || firstProbeId != null) {
          return;
        }
        firstProbeId = id;

        final invalidStamp = DateTime.now().toUtc().toIso8601String();
        socket.add(jsonEncode({
          "type": "timeSyncResponse",
          "id": id,
          "t1": "not-a-date",
          "t2": invalidStamp,
        }));

        Timer(const Duration(milliseconds: 20), () {
          final validStamp = DateTime.now().toUtc().toIso8601String();
          socket.add(jsonEncode({
            "type": "timeSyncResponse",
            "id": id,
            "t1": validStamp,
            "t2": validStamp,
          }));
        });
      });
    });

    final scheduledTaskService = ScheduledTaskService();
    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      scheduledTaskService: scheduledTaskService,
    );
    final calibrated = Completer<TimeSyncResult>();
    void listener() {
      final value = TimeSyncService.instance.latest.value;
      if (value != null && !calibrated.isCompleted) {
        calibrated.complete(value);
      }
    }

    TimeSyncService.instance.latest.addListener(listener);

    try {
      await client.connect();
      final result = await calibrated.future.timeout(
        const Duration(seconds: 5),
      );

      expect(firstProbeId, isNotNull);
      expect(result.sampleCount, 1);
      expect(scheduledTaskService.clockOffset, result.offset);
    } finally {
      TimeSyncService.instance.latest.removeListener(listener);
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
}
