import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/camera_setup_service.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/log_service.dart";
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

  test("message collector ignores socket messages after close", () async {
    final messages = _JsonMessageCollector();

    await messages.close();

    expect(
      () => messages.addJsonMessage(jsonEncode({"type": "deviceId"})),
      returnsNormally,
    );
  });

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
    final messages = _JsonMessageCollector();
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
        messages.addJsonMessage(data as String);
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

  test("slave registration includes app and hardware diagnostics", () async {
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
    final messages = _JsonMessageCollector();
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
        messages.addJsonMessage(data as String);
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () async => null,
      identityPayloadLoader: () async => {
        "appVersion": "1.4.0",
        "appBuildNumber": "16",
        "hardware": "Samsung Galaxy S10e",
      },
    );

    try {
      await client.connect();
      final first = await messages.stream.first.timeout(
        const Duration(milliseconds: 200),
      );

      expect(first["type"], "deviceId");
      expect(first["deviceId"], "test-device");
      expect(first["appVersion"], "1.4.0");
      expect(first["appBuildNumber"], "16");
      expect(first["hardware"], "Samsung Galaxy S10e");
    } finally {
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
    }
  });

  test("disconnect removes recording interruption listener", () {
    final storageService = StorageService(
      messengerState: null,
      lowStorageThreshold: 1.5,
      criticalStorageThreshold: 0.5,
      onCriticalStorageCallback: () async {},
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );
    var stoppedCallbackCount = 0;
    final client = SlaveClient(
      "ws://127.0.0.1:1/ws",
      cameraService: cameraService,
      networkPayloadLoader: () async => null,
      onRecordingStopped: () => stoppedCallbackCount++,
    );

    client.disconnect();
    cameraService.recordingInterrupted.value = true;

    expect(stoppedCallbackCount, 0);
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
    final messages = _JsonMessageCollector();
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
        messages.addJsonMessage(data as String);
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
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "slave-session-guid",
      "slave-session-id",
      deviceType: "Slave",
    );
    final photoFile = File(
        "${Directory.systemTemp.createTempSync("slave-heartbeat").path}/photo.jpg")
      ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "test-device",
      captureDate: DateTime.utc(2026, 6, 17, 15),
      receivedDate: DateTime.utc(2026, 6, 17, 15, 0, 1),
    );
    await SessionManager.instance.addPhoto(photo);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = _JsonMessageCollector();
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
        messages.addJsonMessage(data as String);
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
      expect(heartbeat["sessionMedia"], {
        "photoCount": 1,
        "videoCount": 0,
        "pendingUploadCount": 1,
        "uploadedCount": 0,
      });
    } finally {
      client.disconnect();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      await photoFile.parent.delete(recursive: true);
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
    }
  });

  test("noSession preserves an active slave session and upload queue",
      () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
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

    LogService.instance.clearLogs();
    final pathProvider = _TestPathProviderPlatform();
    PathProviderPlatform.instance = pathProvider;
    final uploaderService = UploaderService();
    uploaderService.reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.joinSession(
      "slave-active-session",
      "slave-active-session-id",
      deviceType: "Slave",
    );

    final tempDir = Directory.systemTemp.createTempSync("slave_no_session");
    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedPhoto = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-slave",
      captureDate: DateTime(2026, 6, 17, 16),
      receivedDate: DateTime(2026, 6, 17, 16, 0, 1),
    );
    await uploaderService.addMediaToQueue(capturedPhoto);
    expect(SessionManager.instance.sessionGuid, "slave-active-session");
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
            "command": "noSession",
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
        () =>
            _logContains("No active session on master") ||
            _logContains("Master reported no active session"),
        timeout: const Duration(seconds: 1),
      );

      expect(SessionManager.instance.sessionGuid, "slave-active-session");
      expect(SessionManager.instance.isSessionActive, isTrue);
      expect(uploaderService.queueLength, 1);
    } finally {
      client.disconnect();
      uploaderService.reset();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      pathProvider.dispose();
    }
  });

  test("conflicting sessionStatus preserves active slave session and queue",
      () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
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

    LogService.instance.clearLogs();
    final pathProvider = _TestPathProviderPlatform();
    PathProviderPlatform.instance = pathProvider;
    final uploaderService = UploaderService();
    uploaderService.reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.joinSession(
      "slave-active-session",
      "slave-active-session-id",
      deviceType: "Slave",
    );

    final tempDir = Directory.systemTemp.createTempSync("slave_conflict");
    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedPhoto = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-slave",
      captureDate: DateTime(2026, 6, 17, 16, 15),
      receivedDate: DateTime(2026, 6, 17, 16, 15, 1),
    );
    await uploaderService.addMediaToQueue(capturedPhoto);
    expect(SessionManager.instance.sessionGuid, "slave-active-session");
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
            "command": "sessionStatus",
            "sessionGuid": "master-other-session",
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
        () =>
            _logContains("Session guid: master-other-session") ||
            _logContains("Master session conflict"),
        timeout: const Duration(seconds: 1),
      );

      expect(SessionManager.instance.sessionGuid, "slave-active-session");
      expect(SessionManager.instance.isSessionActive, isTrue);
      expect(uploaderService.queueLength, 1);
    } finally {
      client.disconnect();
      uploaderService.reset();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      pathProvider.dispose();
    }
  });

  test("malformed sessionStatus preserves active slave session and queue",
      () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
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

    LogService.instance.clearLogs();
    final pathProvider = _TestPathProviderPlatform();
    PathProviderPlatform.instance = pathProvider;
    final uploaderService = UploaderService();
    uploaderService.reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.joinSession(
      "slave-active-session",
      "slave-active-session-id",
      deviceType: "Slave",
    );

    final tempDir = Directory.systemTemp.createTempSync("slave_bad_session");
    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedPhoto = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-slave",
      captureDate: DateTime(2026, 6, 18, 17, 55),
      receivedDate: DateTime(2026, 6, 18, 17, 55, 1),
    );
    await uploaderService.addMediaToQueue(capturedPhoto);
    expect(SessionManager.instance.sessionGuid, "slave-active-session");
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
            "command": "sessionStatus",
            "sessionGuid": 42,
          }));
          socket.add(jsonEncode({
            "type": "sessionStarted",
            "sessionGuid": ["not-a-guid"],
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
        () =>
            _logContains("Ignoring sessionStatus without valid sessionGuid") &&
            _logContains("Ignoring sessionStarted without valid sessionGuid"),
        timeout: const Duration(seconds: 1),
      );

      expect(SessionManager.instance.sessionGuid, "slave-active-session");
      expect(SessionManager.instance.isSessionActive, isTrue);
      expect(uploaderService.queueLength, 1);
    } finally {
      client.disconnect();
      uploaderService.reset();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      pathProvider.dispose();
    }
  });

  test("conflicting sessionEnded preserves active slave session and queue",
      () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
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

    LogService.instance.clearLogs();
    final pathProvider = _TestPathProviderPlatform();
    PathProviderPlatform.instance = pathProvider;
    final uploaderService = UploaderService();
    uploaderService.reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.joinSession(
      "slave-active-session",
      "slave-active-session-id",
      deviceType: "Slave",
    );

    final tempDir = Directory.systemTemp.createTempSync("slave_end_conflict");
    final photoFile = File("${tempDir.path}/queued-photo.jpg")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final capturedPhoto = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "queued-slave",
      captureDate: DateTime(2026, 6, 18, 17, 20),
      receivedDate: DateTime(2026, 6, 18, 17, 20, 1),
    );
    await uploaderService.addMediaToQueue(capturedPhoto);
    expect(SessionManager.instance.sessionGuid, "slave-active-session");
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
            "command": "sessionEnded",
            "sessionGuid": "master-other-session",
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
        () =>
            _logContains("Session ended as per master command") ||
            _logContains("Ignoring sessionEnded"),
        timeout: const Duration(seconds: 1),
      );

      expect(SessionManager.instance.sessionGuid, "slave-active-session");
      expect(SessionManager.instance.isSessionActive, isTrue);
      expect(uploaderService.queueLength, 1);
    } finally {
      client.disconnect();
      uploaderService.reset();
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      pathProvider.dispose();
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
            "displayName": "Squash match - Slave Court",
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
      expect(
        SessionManager.instance.currentSession?.displayTitle,
        "Squash match - Slave Court",
      );
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
    SessionManager.instance.joinSession(
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
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "slave-session-guid",
      "slave-session-id",
      deviceType: "Slave",
    );
    final photoFile = File(
        "${Directory.systemTemp.createTempSync("slave-identify").path}/photo.jpg")
      ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    final photo = CapturedPhoto(
      photoPath: photoFile.path,
      slaveDeviceId: "test-device",
      captureDate: DateTime.utc(2026, 6, 17, 15),
      receivedDate: DateTime.utc(2026, 6, 17, 15, 0, 1),
    );
    await SessionManager.instance.addPhoto(photo);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = _JsonMessageCollector();
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
        final decoded = messages.addJsonMessage(data as String);
        if (decoded != null) {
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
      expect(ack["sessionMedia"], {
        "photoCount": 1,
        "videoCount": 0,
        "pendingUploadCount": 1,
        "uploadedCount": 0,
      });
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
      await photoFile.parent.delete(recursive: true);
      for (final socket in sockets) {
        await socket.close();
      }
      await messages.close();
      await server.close(force: true);
    }
  });

  test("identifyAck is suppressed when disconnected during payload load",
      () async {
    SharedPreferences.setMockInitialValues({
      "device_id": "test-device",
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

    LogService.instance.clearLogs();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final messages = _JsonMessageCollector();
    final networkPayload = Completer<Map<String, dynamic>?>();
    final networkPayloadStarted = Completer<void>();
    var networkPayloadLoadCount = 0;
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
        final decoded = messages.addJsonMessage(data as String);
        if (decoded != null && decoded["type"] == "deviceId" && !identifySent) {
          identifySent = true;
          socket.add(jsonEncode({
            "command": "identifySlave",
            "requestId": "disconnect-race",
          }));
        }
      });
    });

    final client = SlaveClient(
      "ws://127.0.0.1:${server.port}/ws",
      networkPayloadLoader: () {
        networkPayloadLoadCount += 1;
        if (networkPayloadLoadCount == 1) {
          return Future<Map<String, dynamic>?>.value(null);
        }
        if (!networkPayloadStarted.isCompleted) {
          networkPayloadStarted.complete();
        }
        return networkPayload.future;
      },
    );

    try {
      await client.connect();
      await networkPayloadStarted.future.timeout(const Duration(seconds: 1));

      client.disconnect();
      networkPayload.complete({
        "isWifiActive": true,
        "ipAddress": "192.168.178.62",
        "source": "disconnect-race",
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        messages.messages.where((message) => message["type"] == "identifyAck"),
        isEmpty,
      );
      expect(
        _logContains("Error decoding or processing message in processcommand"),
        isFalse,
      );
    } finally {
      client.disconnect();
      if (!networkPayload.isCompleted) {
        networkPayload.complete(null);
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

  test("disconnect cancels pending scheduled slave commands", () async {
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

    final slaveNow = DateTime.utc(2026, 6, 18, 20, 7);
    final scheduledTime = slaveNow.add(const Duration(seconds: 30));
    final taskId = "slave:takePhoto:${scheduledTime.toIso8601String()}";
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

      expect(scheduledTaskService.isTaskScheduled(taskId), isTrue);

      client.disconnect();

      expect(scheduledTaskService.isTaskScheduled(taskId), isFalse);
    } finally {
      scheduledTaskService.cancelTask(taskId);
      client.disconnect();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
}

class _JsonMessageCollector {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
  var _isClosed = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Map<String, dynamic>? addJsonMessage(String data) {
    if (_isClosed) {
      return null;
    }
    final decoded = jsonDecode(data);
    if (decoded is Map<String, dynamic> && !_isClosed) {
      messages.add(decoded);
      _controller.add(decoded);
      return decoded;
    }
    return null;
  }

  Future<void> close() {
    _isClosed = true;
    return _controller.close();
  }
}

bool _logContains(String text) {
  return LogService.instance.logs.any(
    (log) => log["message"]?.toString().contains(text) ?? false,
  );
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
