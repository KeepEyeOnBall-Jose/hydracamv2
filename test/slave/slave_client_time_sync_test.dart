import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/sync_metadata.dart";
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

  test("disconnect clears calibration and scheduled clock offset", () {
    final scheduledTaskService = ScheduledTaskService();
    final client = SlaveClient(
      "ws://127.0.0.1:1/ws",
      networkPayloadLoader: () async => null,
      scheduledTaskService: scheduledTaskService,
    );

    TimeSyncService.instance.record(TimeSyncResult(
      offset: const Duration(milliseconds: 80),
      uncertainty: const Duration(milliseconds: 10),
      minRoundTrip: const Duration(milliseconds: 20),
      sampleCount: 8,
      confidence: TimeSyncConfidence.green,
      calibratedAt: DateTime.now().toUtc(),
    ));
    scheduledTaskService.updateClockOffset(const Duration(milliseconds: 80));

    client.disconnect();

    expect(TimeSyncService.instance.latest.value, isNull);
    expect(scheduledTaskService.clockOffset, Duration.zero);
  });

  test("scheduled master-time fallback only replaces stale calibration",
      () async {
    final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final socketReady = Completer<WebSocket>();
    final scheduled = Completer<void>();
    final staleScheduled = Completer<void>();
    var scheduleCount = 0;

    server.listen((request) async {
      if (request.uri.path != "/ws") {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socketReady.complete(socket);
      socket.listen((_) {});
    });

    final scheduledTaskService = ScheduledTaskService(now: () => now);
    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      scheduledTaskService: scheduledTaskService,
      now: () => now,
      onScheduledCommand: (_, __) {
        scheduleCount += 1;
        if (scheduleCount == 1 && !scheduled.isCompleted) {
          scheduled.complete();
        } else if (scheduleCount == 2 && !staleScheduled.isCompleted) {
          staleScheduled.complete();
        }
      },
    );

    try {
      await client.connect();
      final socket = await socketReady.future.timeout(
        const Duration(seconds: 2),
      );

      TimeSyncService.instance.record(TimeSyncResult(
        offset: const Duration(milliseconds: 123),
        uncertainty: const Duration(milliseconds: 150),
        minRoundTrip: const Duration(milliseconds: 300),
        sampleCount: 2,
        confidence: TimeSyncConfidence.red,
        calibratedAt: now,
      ));
      scheduledTaskService.updateClockOffset(
        const Duration(milliseconds: 123),
      );

      socket.add(jsonEncode({
        "type": "scheduledCommand",
        "command": "stopCamera",
        "scheduledTime": now.add(const Duration(hours: 1)).toIso8601String(),
        "masterTime": now.add(const Duration(seconds: 5)).toIso8601String(),
      }));
      await scheduled.future.timeout(const Duration(seconds: 2));

      expect(
        scheduledTaskService.clockOffset,
        const Duration(milliseconds: 123),
      );

      TimeSyncService.instance.record(TimeSyncResult(
        offset: const Duration(milliseconds: 123),
        uncertainty: const Duration(milliseconds: 20),
        minRoundTrip: const Duration(milliseconds: 40),
        sampleCount: 8,
        confidence: TimeSyncConfidence.green,
        calibratedAt: now.subtract(const Duration(seconds: 121)),
      ));

      socket.add(jsonEncode({
        "type": "scheduledCommand",
        "command": "stopCamera",
        "scheduledTime": now.add(const Duration(hours: 2)).toIso8601String(),
        "masterTime": now.add(const Duration(seconds: 5)).toIso8601String(),
      }));

      await staleScheduled.future.timeout(const Duration(seconds: 2));
      expect(scheduledTaskService.clockOffset, const Duration(seconds: 5));
    } finally {
      client.disconnect();
      await server.close(force: true);
    }
  });
}
