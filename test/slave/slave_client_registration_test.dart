import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/services/camera_setup_service.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/scheduled_task_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/settings_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/slave/slave_client.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
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

  test("slave heartbeat includes camera setup status when available", () async {
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
    CameraSetupService.instance.setPerspective(
      CameraPerspectiveMetadata.fromId("tin_back_floor_center"),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = StreamController<Map<String, dynamic>>.broadcast();
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
      networkPayloadLoader: () async => null,
    );

    try {
      await client.connect();
      final heartbeat = await messages.stream
          .firstWhere((message) => message["type"] == "heartbeat")
          .timeout(const Duration(seconds: 1));

      expect(heartbeat["setupStatus"], {
        "cameraPerspectiveId": "tin_back_floor_center",
        "cameraPerspectiveLabel": "Tin to back, floor, centered",
        "isLevel": false,
        "sensorAvailable": false,
      });
    } finally {
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
      CameraSetupService.instance.resetForTest();
    }
  });

  test("slave heartbeat reports active session guid", () async {
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
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "slave-session-guid",
      "slave-session-id",
      deviceType: "Slave",
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = StreamController<Map<String, dynamic>>.broadcast();
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
      networkPayloadLoader: () async => null,
    );

    try {
      await client.connect();
      final heartbeat = await messages.stream
          .firstWhere((message) => message["type"] == "heartbeat")
          .timeout(const Duration(seconds: 1));

      expect(heartbeat["sessionGuid"], "slave-session-guid");
    } finally {
      client.disconnect();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
    }
  });

  test("auto-record starts recording when sessionStarted arrives", () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
      "autograbadoMode": true,
      "autoUploadMaterials": false,
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
    final cameraService = CameraServiceSingleton.instance;
    if (cameraService.isRecording) {
      await cameraService.stopRecordingVideo();
    }
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    expect(await SettingsService.getAutoRecordMode(), isTrue);

    final pathProvider = _TestPathProviderPlatform();
    PathProviderPlatform.instance = pathProvider;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final recordingStarted = Completer<void>();
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
        if (decoded is Map<String, dynamic> && decoded["type"] == "deviceId") {
          socket.add(jsonEncode({
            "command": "sessionStarted",
            "sessionGuid": "auto-record-session",
          }));
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      onRecordingStarted: () {
        if (!recordingStarted.isCompleted) {
          recordingStarted.complete();
        }
      },
    );

    try {
      await client.connect();
      await recordingStarted.future.timeout(const Duration(seconds: 2));

      expect(SessionManager.instance.sessionGuid, "auto-record-session");
      expect(cameraService.isRecording, isTrue);
    } finally {
      client.disconnect();
      if (cameraService.isRecording) {
        await cameraService.stopRecordingVideo();
      }
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      pathProvider.dispose();
    }
  });

  test("startUploadingAll command starts pending upload queue", () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
      "autoUploadMaterials": false,
    });
    final uploaderService = UploaderService();
    uploaderService.reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.joinBackendSession(
      "backend-upload-session",
      "backend-upload-session-id",
      deviceType: "Slave",
    );

    final tempDir = Directory.systemTemp.createTempSync("slave_upload_command");
    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedPhoto = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-slave",
      captureDate: DateTime(2026, 6, 8, 18),
      receivedDate: DateTime(2026, 6, 8, 18, 0, 1),
    );
    await uploaderService.addMediaToQueue(capturedPhoto);
    expect(uploaderService.queueLength, 1);

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
        if (decoded is Map<String, dynamic> && decoded["type"] == "deviceId") {
          socket.add(jsonEncode({
            "command": "startUploadingAll",
          }));
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
    );

    try {
      await client.connect();
      await _waitFor(
        () => uploaderService.queueLength == 0 && !uploaderService.isUploading,
        timeout: const Duration(seconds: 1),
      );

      expect(uploaderService.isUploading, isFalse);
      expect(capturedPhoto.isUploaded, isFalse);
    } finally {
      client.disconnect();
      uploaderService.reset();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  });

  test("identifySlave command replies with identifyAck", () async {
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
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "slave-session-guid",
      "slave-session-id",
      deviceType: "Slave",
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = StreamController<Map<String, dynamic>>.broadcast();
    final sockets = <WebSocket>[];
    var identifySent = false;

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
          if (decoded["type"] == "deviceId" && !identifySent) {
            identifySent = true;
            socket.add(jsonEncode({
              "command": "identifySlave",
              "requestId": "identify-test",
            }));
          }
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => {
        "isWifiActive": true,
        "ipAddress": "192.168.178.62",
        "source": "identify-test",
      },
    );

    try {
      await client.connect();
      final ack = await messages.stream
          .firstWhere((message) => message["type"] == "identifyAck")
          .timeout(const Duration(seconds: 1));

      expect(ack["deviceId"], "test-device");
      expect(ack["requestId"], "identify-test");
      expect(ack["status"], "alive");
      expect(ack["sessionGuid"], "slave-session-guid");
      expect(ack["network"], {
        "isWifiActive": true,
        "ipAddress": "192.168.178.62",
        "source": "identify-test",
      });
    } finally {
      client.disconnect();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
    }
  });

  test("scheduled command applies master clock offset before countdown",
      () async {
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

    final slaveNow = DateTime.utc(2026, 6, 8, 20, 35);
    final masterTime = slaveNow.add(const Duration(seconds: 2));
    final scheduledTime = slaveNow.add(const Duration(seconds: 5));
    final scheduledTaskService = ScheduledTaskService(now: () => slaveNow);
    final scheduledCallback = Completer<void>();
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
        if (decoded is Map<String, dynamic> && decoded["type"] == "deviceId") {
          socket.add(jsonEncode({
            "type": "scheduledCommand",
            "command": "takePhoto",
            "scheduledTime": scheduledTime.toIso8601String(),
            "masterTime": masterTime.toIso8601String(),
          }));
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      scheduledTaskService: scheduledTaskService,
      now: () => slaveNow,
      onScheduledCommand: (command, scheduledTime) {
        if (!scheduledCallback.isCompleted) {
          scheduledCallback.complete();
        }
      },
    );

    try {
      await client.connect();
      await scheduledCallback.future.timeout(const Duration(seconds: 1));

      expect(scheduledTaskService.clockOffset, const Duration(seconds: 2));
      expect(
        scheduledTaskService.delayUntil(scheduledTime),
        const Duration(seconds: 3),
      );
      expect(
        scheduledTaskService.isTaskScheduled(
          "slave:takePhoto:${scheduledTime.toIso8601String()}",
        ),
        isTrue,
      );
    } finally {
      scheduledTaskService.cancelTask(
        "slave:takePhoto:${scheduledTime.toIso8601String()}",
      );
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  final Directory documentsDir =
      Directory.systemTemp.createTempSync("slave_client_docs");

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail("Timed out waiting for condition.");
}
