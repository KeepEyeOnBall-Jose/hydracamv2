import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:hydracam/master/connected_client_automation_payload.dart";
import "package:hydracam/master/master_server.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/session_media_storage.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

class MockHttpServer extends Mock implements HttpServer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pathProvider = _MasterServerPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    pathProvider.resetDocumentsDir();
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    pathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test("master socket binding supports rapid shared rebind", () async {
    final first = await MasterServer.bindMasterSocket(
      address: "127.0.0.1",
      port: 0,
    );
    final second = await MasterServer.bindMasterSocket(
      address: "127.0.0.1",
      port: first.port,
    );

    await second.close(force: true);
    await first.close(force: true);
  });

  test("pending server start closes immediately when stop is requested",
      () async {
    final bindCompleter = Completer<HttpServer>();
    final httpServer = MockHttpServer();
    when(() => httpServer.close(force: any(named: "force")))
        .thenAnswer((_) async => httpServer);
    final server = MasterServer(
      MockCameraService(),
      bindMasterSocket: ({address = "0.0.0.0", port = 4040}) {
        return bindCompleter.future;
      },
    );

    final startFuture = server.startServer();

    server.stopServer();
    bindCompleter.complete(httpServer);
    await startFuture;

    expect(server.serverStartedAt, isNull);
    verify(() => httpServer.close(force: true)).called(1);
  });

  test("master network snapshot cache reuses snapshots inside ttl", () async {
    var calls = 0;
    var now = DateTime(2026, 6, 7, 19);
    final cache = MasterNetworkSnapshotCache(
      ttl: const Duration(seconds: 2),
      now: () => now,
      loadSnapshot: () async {
        calls += 1;
        return NetworkSnapshot(
          isWifiActive: true,
          source: "test",
          ipAddress: "192.168.178.$calls",
        );
      },
    );

    final first = await cache.current();
    now = now.add(const Duration(milliseconds: 500));
    final second = await cache.current();
    now = now.add(const Duration(seconds: 3));
    final third = await cache.current();

    expect(first.ipAddress, "192.168.178.1");
    expect(second.ipAddress, "192.168.178.1");
    expect(third.ipAddress, "192.168.178.2");
    expect(calls, 2);
  });

  test("master session response payloads share one encoded command helper", () {
    final activePayload = jsonDecode(
      encodeMasterSessionStatusResponse("active-session-guid"),
    ) as Map<String, dynamic>;
    final inactivePayload = jsonDecode(
      encodeMasterSessionStatusResponse(null),
    ) as Map<String, dynamic>;

    expect(activePayload, {
      "command": "sessionStatus",
      "sessionGuid": "active-session-guid",
    });
    expect(inactivePayload, {"command": "noSession"});
  });

  test(
      "master server exposes connected client before network refresh completes",
      () async {
    final snapshotCompleter = Completer<NetworkSnapshot>();
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () => snapshotCompleter.future,
      ),
    );
    final socket = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "registration-test",
      ),
    );

    final immediateClients = server.getConnectedDeviceInfos();
    expect(immediateClients, hasLength(1));
    expect(
      immediateClients.single.networkStatus,
      ConnectedDeviceNetworkStatus.unknown,
    );

    snapshotCompleter.complete(const NetworkSnapshot(
      isWifiActive: true,
      ipAddress: "192.168.178.153",
      source: "master-test",
    ));
    await Future<void>.delayed(Duration.zero);

    final refreshedClients = server.getConnectedDeviceInfos();
    expect(refreshedClients, hasLength(1));
    expect(
      refreshedClients.single.networkStatus,
      ConnectedDeviceNetworkStatus.ready,
    );
  });

  test("master server warns slave when stale Wi-Fi identity conflicts with IP",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          bssid: "2c:91:ab:8b:a3:07",
          gatewayIp: "192.168.178.1",
          subnetMask: "255.255.255.0",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "wrong-network-slave",
      socket: socket,
      remoteIp: "10.10.0.20",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "10.10.0.20",
        bssid: "2c:91:ab:8b:a3:07",
        gatewayIp: "192.168.178.1",
        subnetMask: "255.255.255.0",
        source: "stale-slave-test",
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final clients = server.getConnectedDeviceInfos();
    expect(clients.single.networkStatus,
        ConnectedDeviceNetworkStatus.wrongNetwork);
    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    final payload = jsonDecode(sentMessage) as Map<String, dynamic>;
    expect(payload["command"], "networkMismatch");
  });

  test("master server preserves optional camera setup status", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
      setupStatus: const ConnectedDeviceSetupStatus(
        cameraPerspectiveId: "right_backglass_parallel",
        cameraPerspectiveLabel:
            "Right corner, behind glass, parallel to front wall",
        isLevel: true,
        sensorAvailable: true,
      ),
    );

    final client = server.getConnectedDeviceInfos().single;
    expect(client.setupStatus?.cameraPerspectiveId, "right_backglass_parallel");
    expect(client.setupStatus?.isLevel, isTrue);
  });

  test("incoming device registration sends current session status", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "deviceId",
        "deviceId": "slave-a",
        "sessionGuid": "slave-session-guid",
        "network": {
          "isWifiActive": true,
          "ipAddress": "192.168.178.62",
          "source": "slave-test",
        },
      }),
      socket: socket,
      remoteIp: "192.168.178.62",
    );

    expect(server.getConnectedDeviceIds(), ["slave-a"]);
    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    expect(jsonDecode(sentMessage), {"command": "noSession"});
  });

  test("incoming device registration exposes app and hardware diagnostics",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "deviceId",
        "deviceId": "slave-a",
        "appVersion": "1.4.0",
        "appBuildNumber": "16",
        "hardware": "Samsung Galaxy S10e",
      }),
      socket: socket,
      remoteIp: "192.168.178.62",
    );

    final payload =
        buildConnectedClientAutomationPayload(server.getConnectedDeviceInfos());
    final client =
        (payload["connectedClients"] as List).single as Map<String, dynamic>;

    expect(client["appVersion"], "1.4.0");
    expect(client["appBuildNumber"], "16");
    expect(client["hardwareLabel"], "Samsung Galaxy S10e");
  });

  test("incoming heartbeat preserves slave session media diagnostics",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "heartbeat",
        "deviceId": "slave-a",
        "sessionGuid": "slave-session-guid",
        "sessionMedia": {
          "photoCount": 1,
          "videoCount": 0,
          "pendingUploadCount": 1,
          "uploadedCount": 0,
        },
      }),
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
    );

    final payload =
        buildConnectedClientAutomationPayload(server.getConnectedDeviceInfos());
    final client =
        (payload["connectedClients"] as List).single as Map<String, dynamic>;

    expect(client["reportedSessionGuid"], "slave-session-guid");
    expect(client["sessionMedia"], {
      "photoCount": 1,
      "videoCount": 0,
      "pendingUploadCount": 1,
      "uploadedCount": 0,
    });
  });

  test("incoming heartbeat clears stale slave session media diagnostics",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "heartbeat",
        "deviceId": "slave-a",
        "sessionGuid": "slave-session-guid",
        "sessionMedia": {
          "photoCount": 1,
          "videoCount": 0,
          "pendingUploadCount": 1,
          "uploadedCount": 0,
        },
      }),
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
    );

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "heartbeat",
        "deviceId": "slave-a",
      }),
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
    );

    final payload =
        buildConnectedClientAutomationPayload(server.getConnectedDeviceInfos());
    final client =
        (payload["connectedClients"] as List).single as Map<String, dynamic>;

    expect(client["reportedSessionGuid"], isNull);
    expect(client["sessionMedia"], isNull);
  });

  test("incoming photo media is saved through session media storage", () async {
    final galleryCalls = <SessionMediaType>[];
    final storageRoot =
        Directory.systemTemp.createTempSync("master_received_media");
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {
          galleryCalls.add(mediaType);
        },
        now: () => DateTime.fromMillisecondsSinceEpoch(1770000000789),
      ),
    );
    SessionManager.instance.startSession(
      "server-media-guid",
      "server-media-id",
      deviceType: "Master",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "slave-a",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": DateTime.utc(2026, 6, 9, 3, 44).toIso8601String(),
        }),
        socket: MockWebSocket(),
      );

      final photos =
          SessionManager.instance.currentSession?.capturedPhotos ?? [];
      final expectedPath =
          "${storageRoot.path}/session_server-media-guid/media_1770000000789.jpg";
      expect(photos, hasLength(1));
      expect(photos.single.photoPath, expectedPath);
      expect(photos.single.slaveDeviceId, "slave-a");
      expect(File(expectedPath).readAsBytesSync(), [0xFF, 0xD8, 0xFF]);
      expect(galleryCalls, [SessionMediaType.photo]);
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });

  test("incoming photo media from stale slave session is ignored", () async {
    final galleryCalls = <SessionMediaType>[];
    final storageRoot =
        Directory.systemTemp.createTempSync("master_stale_media");
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {
          galleryCalls.add(mediaType);
        },
        now: () => DateTime.fromMillisecondsSinceEpoch(1770000000789),
      ),
    );
    SessionManager.instance.startSession(
      "current-master-session",
      "current-master-id",
      deviceType: "Master",
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "stale-slave",
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
      reportedSessionGuid: "old-slave-session",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "stale-slave",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": DateTime.utc(2026, 6, 18, 17, 25).toIso8601String(),
        }),
        socket: MockWebSocket(),
      );

      final photos =
          SessionManager.instance.currentSession?.capturedPhotos ?? [];
      expect(photos, isEmpty);
      expect(galleryCalls, isEmpty);
      expect(
        Directory("${storageRoot.path}/session_current-master-session")
            .existsSync(),
        isFalse,
      );
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });

  test("incoming photo media with malformed timestamp is ignored before save",
      () async {
    final galleryCalls = <SessionMediaType>[];
    final storageRoot =
        Directory.systemTemp.createTempSync("master_malformed_media");
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {
          galleryCalls.add(mediaType);
        },
        now: () => DateTime.fromMillisecondsSinceEpoch(1770000000789),
      ),
    );
    SessionManager.instance.startSession(
      "malformed-master-session",
      "malformed-master-id",
      deviceType: "Master",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "slave-a",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": "not-a-date",
        }),
        socket: MockWebSocket(),
      );

      final photos =
          SessionManager.instance.currentSession?.capturedPhotos ?? [];
      expect(photos, isEmpty);
      expect(galleryCalls, isEmpty);
      expect(
        Directory("${storageRoot.path}/session_malformed-master-session")
            .existsSync(),
        isFalse,
      );
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });

  test("stale socket close does not remove current client registration",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final firstSocket = MockWebSocket();
    final secondSocket = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: firstSocket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: secondSocket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    server.removeClientIfCurrentForTest(
      deviceId: "slave-a",
      socket: firstSocket,
    );

    expect(server.getConnectedDeviceInfos(), hasLength(1));
    expect(server.getConnectedDeviceInfos().single.isConnected, isTrue);
    expect(server.getConnectedDeviceIds(), ["slave-a"]);

    server.removeClientIfCurrentForTest(
      deviceId: "slave-a",
      socket: secondSocket,
    );

    expect(server.getConnectedDeviceIds(), isEmpty);
    expect(server.getConnectedDeviceInfos(), hasLength(1));
    expect(server.getConnectedDeviceInfos().single.isConnected, isFalse);
  });

  test("master server retains disconnected device status after socket removal",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    expect(server.getConnectedDeviceIds(), ["slave-a"]);

    server.removeClientIfCurrentForTest(
      deviceId: "slave-a",
      socket: socket,
    );

    expect(server.getConnectedDeviceIds(), isEmpty);
    final devices = server.getConnectedDeviceInfos();
    expect(devices, hasLength(1));
    expect(devices.single.deviceId, "slave-a");
    expect(devices.single.isConnected, isFalse);
    expect(devices.single.connectionStatusLabel, "Disconnected");
    expect(devices.single.disconnectedAt, isNotNull);
  });

  test("stopServer clears transport state without ending the active session",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    when(() => socket.close(
          any<int?>(),
          any<String?>(),
        )).thenAnswer((_) async {});
    SessionManager.instance.startSession(
      "stop-server-session-guid",
      "stop-server-session-id",
      deviceType: "Master",
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    server.stopServer();

    expect(server.getConnectedDeviceIds(), isEmpty);
    expect(server.getConnectedDeviceInfos(), isEmpty);
    expect(SessionManager.instance.isSessionActive, isTrue);
    expect(SessionManager.instance.sessionGuid, "stop-server-session-guid");
    verify(() => socket.close(
          WebSocketStatus.normalClosure,
          "Server shutting down",
        )).called(1);

    await server.endCurrentSession();

    expect(SessionManager.instance.isSessionActive, isFalse);
  });

  test("master server orders connected devices before disconnected history",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final staleSocket = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "a-stale-slave",
      socket: staleSocket,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );
    server.removeClientIfCurrentForTest(
      deviceId: "a-stale-slave",
      socket: staleSocket,
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "z-live-slave",
      socket: MockWebSocket(),
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    final devices = server.getConnectedDeviceInfos();

    expect(devices.map((device) => device.deviceId), [
      "z-live-slave",
      "a-stale-slave",
    ]);
  });

  test("scheduled commands include master send time for slave clock offset",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    final scheduledTime = DateTime.utc(2026, 6, 8, 20, 35, 5);
    final masterTime = DateTime.utc(2026, 6, 8, 20, 35, 2);

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    server.scheduleCommand(
      "takePhoto",
      scheduledTime,
      deviceId: "slave-a",
      masterTime: masterTime,
    );

    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    final payload = jsonDecode(sentMessage) as Map<String, dynamic>;

    expect(payload["type"], "scheduledCommand");
    expect(payload["command"], "takePhoto");
    expect(payload["scheduledTime"], scheduledTime.toIso8601String());
    expect(payload["masterTime"], masterTime.toIso8601String());
  });

  test("scheduled command for missing slave does not broadcast", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socketA = MockWebSocket();
    final socketB = MockWebSocket();
    final scheduledTime = DateTime.utc(2026, 6, 9, 2, 20);

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socketA,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-b",
      socket: socketB,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );

    server.scheduleCommand(
      "takePhoto",
      scheduledTime,
      deviceId: "missing-slave",
      masterTime: scheduledTime,
    );

    verifyNever(() => socketA.add(any()));
    verifyNever(() => socketB.add(any()));
  });

  test("scheduled broadcast sends to all eligible connected slaves", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socketA = MockWebSocket();
    final socketB = MockWebSocket();
    final scheduledTime = DateTime.utc(2026, 6, 9, 2, 20);

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socketA,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-b",
      socket: socketB,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );

    server.scheduleCommand(
      "startRecordingVideo",
      scheduledTime,
      masterTime: scheduledTime,
    );

    final payloadA = jsonDecode(
      verify(() => socketA.add(captureAny())).captured.single as String,
    ) as Map<String, dynamic>;
    final payloadB = jsonDecode(
      verify(() => socketB.add(captureAny())).captured.single as String,
    ) as Map<String, dynamic>;

    expect(payloadA["type"], "scheduledCommand");
    expect(payloadA["command"], "startRecordingVideo");
    expect(payloadA["scheduledTime"], scheduledTime.toIso8601String());
    expect(payloadA["masterTime"], scheduledTime.toIso8601String());
    expect(payloadB, payloadA);
  });

  test("targeted command for missing slave does not broadcast", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socketA = MockWebSocket();
    final socketB = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socketA,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-b",
      socket: socketB,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );

    server.sendCommand("takePhoto", deviceId: "missing-slave");

    verifyNever(() => socketA.add(any()));
    verifyNever(() => socketB.add(any()));
  });

  test("targeted command only sends to the requested connected slave",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socketA = MockWebSocket();
    final socketB = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socketA,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-b",
      socket: socketB,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );

    server.sendCommand("takePhoto", deviceId: "slave-a");

    verify(() => socketA.add("takePhoto")).called(1);
    verifyNever(() => socketB.add(any()));
  });

  test("broadcast command sends to all eligible connected slaves", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socketA = MockWebSocket();
    final socketB = MockWebSocket();

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socketA,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "slave-b",
      socket: socketB,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
    );

    server.sendCommand("stopRecordingVideo");

    verify(() => socketA.add("stopRecordingVideo")).called(1);
    verify(() => socketB.add("stopRecordingVideo")).called(1);
  });

  test("broadcast command skips slaves reporting a different session",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final matchingSocket = MockWebSocket();
    final staleSessionSocket = MockWebSocket();
    SessionManager.instance.startSession(
      "master-session-guid",
      "master-session-id",
      deviceType: "Master",
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "matching-slave",
      socket: matchingSocket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
      reportedSessionGuid: "master-session-guid",
    );
    await server.registerOrUpdateClientForTest(
      deviceId: "stale-session-slave",
      socket: staleSessionSocket,
      remoteIp: "192.168.178.63",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.63",
        source: "slave-test",
      ),
      reportedSessionGuid: "other-session-guid",
    );

    server.sendCommand("takePhoto");

    verify(() => matchingSocket.add("takePhoto")).called(1);
    verifyNever(() => staleSessionSocket.add(any()));
  });

  test("master sends identify command and records ack diagnostics", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    final requestedAt = DateTime.utc(2026, 6, 8, 21, 35);
    final acknowledgedAt = DateTime.utc(2026, 6, 8, 21, 35, 1);

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    final sent = server.sendIdentifyCommand(
      deviceId: "slave-a",
      requestId: "identify-test",
      requestedAt: requestedAt,
    );

    expect(sent, isTrue);
    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    final payload = jsonDecode(sentMessage) as Map<String, dynamic>;
    expect(payload, {
      "command": "identifySlave",
      "requestId": "identify-test",
      "requestedAt": requestedAt.toIso8601String(),
    });

    await server.handleIncomingMessageForTest(
      jsonEncode({
        "type": "identifyAck",
        "deviceId": "slave-a",
        "requestId": "identify-test",
        "timestamp": acknowledgedAt.toIso8601String(),
        "sessionGuid": "slave-session-guid",
        "network": {
          "isWifiActive": true,
          "ipAddress": "192.168.178.64",
          "source": "identify-ack-test",
        },
        "sessionMedia": {
          "photoCount": 2,
          "videoCount": 1,
          "pendingUploadCount": 1,
          "uploadedCount": 2,
        },
      }),
      socket: socket,
      remoteIp: "192.168.178.62",
    );

    final client = server.getConnectedDeviceInfos().single;
    expect(client.identifyStatus, "acknowledged");
    expect(client.identifyStatusLabel, "Identify acknowledged");
    expect(client.lastIdentifyRequestId, "identify-test");
    expect(client.lastIdentifyRequestedAt, requestedAt);
    expect(client.lastIdentifyAckAt, acknowledgedAt);
    expect(client.reportedSessionGuid, "slave-session-guid");
    expect(client.networkSnapshot?.ipAddress, "192.168.178.64");
    expect(client.networkSnapshot?.source, "identify-ack-test");
    expect(client.sessionMedia, {
      "photoCount": 2,
      "videoCount": 1,
      "pendingUploadCount": 1,
      "uploadedCount": 2,
    });
  });

  test("identify command still reaches slaves reporting a different session",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    final requestedAt = DateTime.utc(2026, 6, 17, 19, 5);
    SessionManager.instance.startSession(
      "master-session-guid",
      "master-session-id",
      deviceType: "Master",
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "stale-session-slave",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
      reportedSessionGuid: "other-session-guid",
    );

    final sent = server.sendIdentifyCommand(
      deviceId: "stale-session-slave",
      requestId: "identify-stale-session",
      requestedAt: requestedAt,
    );

    expect(sent, isTrue);
    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    final payload = jsonDecode(sentMessage) as Map<String, dynamic>;
    expect(payload["command"], "identifySlave");
    expect(payload["requestId"], "identify-stale-session");
  });

  test("ending master session broadcasts the ended session guid", () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    SessionManager.instance.startSession(
      "master-session-guid",
      "master-session-id",
      deviceType: "Master",
    );

    await server.registerOrUpdateClientForTest(
      deviceId: "matching-slave",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
      reportedSessionGuid: "master-session-guid",
    );

    await server.endCurrentSession();

    final sentMessage =
        verify(() => socket.add(captureAny())).captured.single as String;
    final payload = jsonDecode(sentMessage) as Map<String, dynamic>;
    expect(payload, {
      "command": "sessionEnded",
      "sessionGuid": "master-session-guid",
    });
    expect(SessionManager.instance.isSessionActive, isFalse);
  });

  test("pending identify becomes unavailable when the slave disconnects",
      () async {
    final server = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
    );
    final socket = MockWebSocket();
    final requestedAt = DateTime.utc(2026, 6, 17, 18, 10);

    await server.registerOrUpdateClientForTest(
      deviceId: "slave-a",
      socket: socket,
      remoteIp: "192.168.178.62",
      networkSnapshot: const NetworkSnapshot(
        isWifiActive: true,
        ipAddress: "192.168.178.62",
        source: "slave-test",
      ),
    );

    final sent = server.sendIdentifyCommand(
      deviceId: "slave-a",
      requestId: "identify-before-disconnect",
      requestedAt: requestedAt,
    );
    expect(sent, isTrue);

    server.removeClientIfCurrentForTest(
      deviceId: "slave-a",
      socket: socket,
    );

    final client = server.getConnectedDeviceInfos().single;
    expect(client.isConnected, isFalse);
    expect(client.identifyStatus, "unavailable");
    expect(client.identifyStatusLabel, "Identify unavailable: disconnected");
    expect(client.lastIdentifyRequestId, "identify-before-disconnect");
    expect(client.lastIdentifyRequestedAt, requestedAt);
    expect(client.lastIdentifyAckAt, isNull);
  });

  test("disconnected device reports preview unavailable by disconnection",
      () async {
    final client = ConnectedDeviceInfo(
      deviceId: "stale-preview-slave",
      networkStatus: ConnectedDeviceNetworkStatus.ready,
      registeredAt: DateTime.utc(2026, 6, 17, 18, 30),
      lastSeen: DateTime.utc(2026, 6, 17, 18, 30, 5),
      isConnected: false,
      disconnectedAt: DateTime.utc(2026, 6, 17, 18, 30, 5),
    );

    expect(client.previewStatus, "unavailableDisconnected");
    expect(client.previewStatusLabel, "Preview unavailable: disconnected");
    expect(client.previewTransportLabel, "Slave disconnected");
  });
}

class _MasterServerPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??= Directory.systemTemp.createTempSync("master_server_docs");
    return _documentsDir!.path;
  }

  void resetDocumentsDir() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }

  void dispose() {
    resetDocumentsDir();
  }
}
