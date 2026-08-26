import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:hydracam/constants.dart";
import "package:hydracam/master/master_server.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/session_media_storage.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

/// Builds a [MockWebSocket] whose void/`Future` returning members are stubbed so
/// the server can call `add`/`close` without a `MissingStubError`.
MockWebSocket buildMockSocket() {
  final socket = MockWebSocket();
  when(() => socket.close(any(), any())).thenAnswer((_) async {});
  when(() => socket.close(any())).thenAnswer((_) async {});
  when(() => socket.close()).thenAnswer((_) async {});
  return socket;
}

/// A [NetworkSnapshot] on a well-known private subnet, so
/// [NetworkInfoService.compareDeviceNetwork] can decide same/different network
/// deterministically.
NetworkSnapshot snapshotFor(String ipAddress) {
  return NetworkSnapshot(
    isWifiActive: true,
    ipAddress: ipAddress,
    source: "master-server-test",
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _MasterServerPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
    registerFallbackValue(_FakeWebSocket());
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

  /// A server whose master-network snapshot is injected (never probes real
  /// Wi-Fi) and whose media storage writes into [storageRoot]. Pass [now] to
  /// drive every server timestamp from a test-controlled clock.
  MasterServer buildServer({
    required Directory storageRoot,
    String masterIp = "192.168.1.10",
    DateTime Function()? now,
  }) {
    return MasterServer(
      MockCameraService(),
      now: now,
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => snapshotFor(masterIp),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {},
      ),
    );
  }

  group("startServer / stopServer lifecycle", () {
    test("startServer binds, accepts a /ws upgrade, and stopServer tears down",
        () async {
      HttpServer? bound;
      final master = MasterServer(
        MockCameraService(),
        masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
          loadSnapshot: () async => snapshotFor("127.0.0.1"),
        ),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          return bound!;
        },
      );

      try {
        await master.startServer();
        expect(bound, isNotNull);
        expect(master.serverStartedAt, isNotNull);

        final client =
            await WebSocket.connect("ws://127.0.0.1:${bound!.port}/ws");
        final firstReply = Completer<String>();
        client.listen((data) {
          if (!firstReply.isCompleted) {
            firstReply.complete(data as String);
          }
        });

        client.add(jsonEncode({"type": "deviceId", "deviceId": "slave-real"}));

        // The server answers a registration with a session-status frame.
        final reply = await firstReply.future.timeout(
          const Duration(seconds: 3),
        );
        expect(jsonDecode(reply)["command"], "noSession");

        await _waitFor(
          () => master.getConnectedDeviceIds().contains("slave-real"),
          description: "slave-real to register",
        );

        await client.close();
      } finally {
        master.stopServer();
        await bound?.close(force: true);
      }
    });

    test("non-/ws requests are rejected with 403 forbidden", () async {
      HttpServer? bound;
      final master = MasterServer(
        MockCameraService(),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          return bound!;
        },
      );

      try {
        await master.startServer();
        // The test binding forces HttpClient to return 400, so issue the
        // request over a raw socket and read the HTTP status line directly.
        final socket = await Socket.connect("127.0.0.1", bound!.port);
        socket.write("GET /not-ws HTTP/1.1\r\nHost: localhost\r\n\r\n");
        await socket.flush();
        final statusLine = await utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .first;
        expect(statusLine, contains("403"));
        await socket.close();
        socket.destroy();
      } finally {
        master.stopServer();
        await bound?.close(force: true);
      }
    });

    test("startServer that is cancelled by stop mid-bind closes the socket",
        () async {
      late final MasterServer master;
      HttpServer? bound;
      master = MasterServer(
        MockCameraService(),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          // Request stop while the bind is "in flight".
          master.stopServer();
          return bound!;
        },
      );

      await master.startServer();

      // Because stop was requested during bind, the server never begins
      // listening and no clients are tracked.
      expect(master.serverStartedAt, isNull);
      expect(master.getConnectedDeviceIds(), isEmpty);
      await bound?.close(force: true);
    });

    test("a bind failure is swallowed and leaves the server unstarted",
        () async {
      final master = MasterServer(
        MockCameraService(),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          throw const SocketException("port in use");
        },
      );

      await master.startServer();
      expect(master.serverStartedAt, isNull);
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("a second startServer does not rebind or restart the heartbeat",
        () async {
      final bound = <HttpServer>[];
      final master = MasterServer(
        MockCameraService(),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          bound.add(server);
          return server;
        },
      );

      try {
        await master.startServer();
        final firstStartedAt = master.serverStartedAt;
        expect(bound, hasLength(1));

        await master.startServer();

        // The duplicate start is ignored outright, so the live HttpServer is
        // never orphaned and no second heartbeat timer is scheduled.
        expect(bound, hasLength(1));
        expect(master.serverStartedAt, firstStartedAt);
      } finally {
        master.stopServer();
        for (final server in bound) {
          await server.close(force: true);
        }
      }
    });

    test("concurrent startServer calls share one bind", () async {
      final bindCompleter = Completer<HttpServer>();
      var bindCalls = 0;
      HttpServer? bound;
      final master = MasterServer(
        MockCameraService(),
        bindMasterSocket: ({Object address = "0.0.0.0", int port = 4040}) {
          bindCalls += 1;
          return bindCompleter.future;
        },
      );

      try {
        final firstStart = master.startServer();
        final secondStart = master.startServer();

        bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        bindCompleter.complete(bound);
        await Future.wait([firstStart, secondStart]);

        expect(bindCalls, 1);
        expect(master.serverStartedAt, isNotNull);
      } finally {
        master.stopServer();
        await bound?.close(force: true);
      }
    });

    test("startServer after stopServer rebinds cleanly", () async {
      final bound = <HttpServer>[];
      final master = MasterServer(
        MockCameraService(),
        bindMasterSocket: (
            {Object address = "0.0.0.0", int port = 4040}) async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          bound.add(server);
          return server;
        },
      );

      try {
        await master.startServer();
        master.stopServer();
        expect(master.serverStartedAt, isNotNull);

        await master.startServer();

        expect(bound, hasLength(2));
        expect(master.getConnectedDeviceIds(), isEmpty);
      } finally {
        master.stopServer();
        for (final server in bound) {
          await server.close(force: true);
        }
      }
    });

    test("stopServer is a no-op when the server was never started", () {
      final master = MasterServer(MockCameraService());
      expect(master.stopServer, returnsNormally);
      expect(master.stopServer, returnsNormally); // idempotent double-stop
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("stopServer clears tracked clients and closes their sockets",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_stop");
      final master = buildServer(storageRoot: storageRoot);
      final socket = buildMockSocket();

      try {
        await master.registerOrUpdateClientForTest(
          deviceId: "slave-a",
          socket: socket,
          remoteIp: "192.168.1.55",
          networkSnapshot: null,
        );
        expect(master.getConnectedDeviceIds(), contains("slave-a"));

        master.stopServer();

        expect(master.getConnectedDeviceIds(), isEmpty);
        expect(master.getConnectedDeviceInfos(), isEmpty);
        verify(() => socket.close(any(), any())).called(1);
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });
  });

  group("client registration handshake (handleIncomingMessageForTest)", () {
    test("a deviceId frame registers the client and replies with noSession",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_reg");
      final master = buildServer(storageRoot: storageRoot);
      final socket = buildMockSocket();

      try {
        await master.handleIncomingMessageForTest(
          jsonEncode({
            "type": "deviceId",
            "deviceId": "slave-a",
            "appVersion": "1.2.3",
            "hardware": "Pixel 7",
          }),
          socket: socket,
          remoteIp: "192.168.1.55",
        );

        expect(master.getConnectedDeviceIds(), contains("slave-a"));
        final info = master.getConnectedDeviceInfos().single;
        expect(info.appVersion, "1.2.3");
        expect(info.hardwareLabel, "Pixel 7");
        expect(info.isConnected, isTrue);

        final sent =
            verify(() => socket.add(captureAny())).captured.single as String;
        expect(jsonDecode(sent)["command"], "noSession");
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("a deviceId frame replies with sessionStatus when a session is active",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_reg_session");
      final master = buildServer(storageRoot: storageRoot);
      final socket = buildMockSocket();
      SessionManager.instance.startSession(
        "session-guid-1",
        "session-id-1",
        deviceType: "Master",
        displayName: "Court 1",
      );

      try {
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "deviceId", "deviceId": "slave-a"}),
          socket: socket,
          remoteIp: "192.168.1.55",
        );

        final sent =
            verify(() => socket.add(captureAny())).captured.single as String;
        final decoded = jsonDecode(sent) as Map<String, dynamic>;
        expect(decoded["command"], "sessionStatus");
        expect(decoded["sessionGuid"], "session-guid-1");
        expect(decoded["displayName"], "Court 1");
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("a registration frame with no deviceId is rejected, not tracked",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_unknown");
      final master = buildServer(storageRoot: storageRoot);
      final socket = buildMockSocket();

      try {
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "deviceId"}),
          socket: socket,
          remoteIp: null,
        );

        expect(master.getConnectedDeviceIds(), isEmpty);
        expect(master.getConnectedDeviceInfos(), isEmpty);
        // No session-status handshake is sent to an unidentified slave.
        verifyNever(() => socket.add(any()));
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("a blank or whitespace-only deviceId counts as unidentified",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_blank_id");
      final master = buildServer(storageRoot: storageRoot);

      try {
        for (final blankId in ["", "   "]) {
          await master.handleIncomingMessageForTest(
            jsonEncode({"type": "deviceId", "deviceId": blankId}),
            socket: buildMockSocket(),
            remoteIp: null,
          );
        }

        expect(master.getConnectedDeviceIds(), isEmpty);
        expect(master.getConnectedDeviceInfos(), isEmpty);
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("unidentified slaves never collide on a shared placeholder entry",
        () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_collision");
      final master = buildServer(storageRoot: storageRoot);
      final identified = buildMockSocket();

      try {
        // Two anonymous slaves plus one that identifies itself. Previously all
        // three shared a single "Unknown"/deviceId entry, so the anonymous
        // pair overwrote each other and the real slave's socket could be lost.
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "deviceId"}),
          socket: buildMockSocket(),
          remoteIp: "192.168.1.55",
        );
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "heartbeat"}),
          socket: buildMockSocket(),
          remoteIp: "192.168.1.56",
        );
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "deviceId", "deviceId": "slave-a"}),
          socket: identified,
          remoteIp: "192.168.1.57",
        );

        expect(master.getConnectedDeviceIds(), ["slave-a"]);
        expect(master.getConnectedDeviceInfos().single.deviceId, "slave-a");
        expect(master.getConnectedDeviceIds(), isNot(contains("Unknown")));
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("state-changing frames without a deviceId are all rejected", () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_anon_frames");
      final master = buildServer(storageRoot: storageRoot);

      try {
        for (final type in ["deviceId", "heartbeat", "identifyAck", "photo"]) {
          await master.handleIncomingMessageForTest(
            jsonEncode({"type": type}),
            socket: buildMockSocket(),
            remoteIp: "192.168.1.55",
          );
        }

        expect(master.getConnectedDeviceIds(), isEmpty);
        expect(master.getConnectedDeviceInfos(), isEmpty);
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });

    test("stateless frames still work without a deviceId", () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_anon_stateless");
      final master = buildServer(storageRoot: storageRoot);
      final socket = buildMockSocket();

      try {
        await master.handleIncomingMessageForTest(
          jsonEncode({"type": "getSessionStatus"}),
          socket: socket,
          remoteIp: null,
        );

        final sent =
            verify(() => socket.add(captureAny())).captured.single as String;
        expect(jsonDecode(sent)["command"], "noSession");
        expect(master.getConnectedDeviceIds(), isEmpty);
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });
  });

  group("message routing", () {
    late Directory storageRoot;
    late MasterServer master;

    setUp(() {
      storageRoot = Directory.systemTemp.createTempSync("master_server_route");
      master = buildServer(storageRoot: storageRoot);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    test("heartbeat frame tracks the client as connected", () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        jsonEncode({"type": "heartbeat", "deviceId": "slave-a"}),
        socket: socket,
        remoteIp: "192.168.1.55",
      );
      expect(master.getConnectedDeviceIds(), contains("slave-a"));
    });

    test("getSessionStatus replies without registering the socket", () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        jsonEncode({"type": "getSessionStatus", "deviceId": "slave-a"}),
        socket: socket,
        remoteIp: "192.168.1.55",
      );

      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      expect(jsonDecode(sent)["command"], "noSession");
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("identifyAck records the acknowledgement on the client info",
        () async {
      final socket = buildMockSocket();
      final ackAt = DateTime.utc(2026, 6, 9, 3, 40);
      await master.handleIncomingMessageForTest(
        jsonEncode({
          "type": "identifyAck",
          "deviceId": "slave-a",
          "requestId": "identify-42",
          "timestamp": ackAt.toIso8601String(),
        }),
        socket: socket,
        remoteIp: "192.168.1.55",
      );

      final info = master.getConnectedDeviceInfos().single;
      expect(info.lastIdentifyRequestId, "identify-42");
      expect(info.lastIdentifyAckAt, ackAt);
      expect(info.identifyStatus, "acknowledged");
    });

    test("timeSyncRequest is answered with an echoed timeSyncResponse",
        () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        jsonEncode({
          "type": "timeSyncRequest",
          "deviceId": "slave-a",
          "id": "9:1",
          "t0": "2026-01-01T00:00:00.000Z",
        }),
        socket: socket,
        remoteIp: null,
      );

      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      final decoded = jsonDecode(sent) as Map<String, dynamic>;
      expect(decoded["type"], "timeSyncResponse");
      expect(decoded["id"], "9:1");
      expect(decoded["t0"], "2026-01-01T00:00:00.000Z");
      expect(decoded.containsKey("t1"), isTrue);
      expect(decoded.containsKey("t2"), isTrue);
    });

    test("forcedStop is logged exactly once, without registering or replying",
        () async {
      final socket = buildMockSocket();
      LogService.instance.clearLogs();

      await master.handleIncomingMessageForTest(
        jsonEncode({
          "type": "forcedStop",
          "deviceId": "slave-a",
          "reason": "battery",
        }),
        socket: socket,
        remoteIp: null,
      );

      verifyNever(() => socket.add(any()));
      expect(master.getConnectedDeviceIds(), isEmpty);

      final forcedStopLogs = LogService.instance.logs
          .map((entry) => entry["message"] as String)
          .where((message) => message.contains("forcibly stopped"))
          .toList();
      expect(forcedStopLogs, [
        "Slave slave-a forcibly stopped. Reason: battery",
      ]);
    });

    test("an unknown message type is ignored without error", () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        jsonEncode({"type": "totallyUnknown", "deviceId": "slave-a"}),
        socket: socket,
        remoteIp: null,
      );
      verifyNever(() => socket.add(any()));
      // The device id is still parsed but the socket is not registered.
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("invalid JSON is swallowed and does not register a client", () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        "this is not json {",
        socket: socket,
        remoteIp: null,
      );
      verifyNever(() => socket.add(any()));
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("a non-map JSON payload is ignored", () async {
      final socket = buildMockSocket();
      await master.handleIncomingMessageForTest(
        jsonEncode([1, 2, 3]),
        socket: socket,
        remoteIp: null,
      );
      verifyNever(() => socket.add(any()));
      expect(master.getConnectedDeviceIds(), isEmpty);
    });

    test("inbound media on a mismatched session is ignored", () async {
      SessionManager.instance.startSession(
        "master-session",
        "master-id",
        deviceType: "Master",
      );
      final socket = buildMockSocket();
      // Register the slave as reporting a *different* session guid.
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: "192.168.1.55",
        networkSnapshot: null,
        reportedSessionGuid: "some-other-session",
      );

      await master.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "slave-a",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": DateTime.utc(2026, 6, 9, 3, 44).toIso8601String(),
        }),
        socket: socket,
        remoteIp: "192.168.1.55",
      );

      expect(
        SessionManager.instance.currentSession?.capturedPhotos ?? const [],
        isEmpty,
      );
    });
  });

  group("command dispatch", () {
    late Directory storageRoot;
    late MasterServer master;

    setUp(() {
      storageRoot = Directory.systemTemp.createTempSync("master_server_cmd");
      master = buildServer(storageRoot: storageRoot);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    Future<MockWebSocket> registerReady(String deviceId) async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: deviceId,
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      clearInteractions(socket);
      return socket;
    }

    test("sendCommand broadcasts to every eligible connected slave", () async {
      final socketA = await registerReady("slave-a");
      final socketB = await registerReady("slave-b");

      master.sendCommand("takePhoto");

      verify(() => socketA.add("takePhoto")).called(1);
      verify(() => socketB.add("takePhoto")).called(1);
    });

    test("sendCommand with a deviceId targets only that slave", () async {
      final socketA = await registerReady("slave-a");
      final socketB = await registerReady("slave-b");

      master.sendCommand("takePhoto", deviceId: "slave-a");

      verify(() => socketA.add("takePhoto")).called(1);
      verifyNever(() => socketB.add(any()));
    });

    test("sendCommand to an unconnected device sends nothing", () async {
      final socketA = await registerReady("slave-a");
      master.sendCommand("takePhoto", deviceId: "ghost");
      verifyNever(() => socketA.add(any()));
    });

    test("sendCommand with no clients connected does not throw", () {
      expect(() => master.sendCommand("takePhoto"), returnsNormally);
    });

    test("sendCommand is blocked for a slave on the wrong network", () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: "10.0.0.5",
        // Slave on 10.0.0.0/24 while master is on 192.168.1.0/24.
        networkSnapshot: snapshotFor("10.0.0.5"),
      );
      await pumpEventQueue();
      expect(
        master.getConnectedDeviceInfos().single.networkStatus,
        ConnectedDeviceNetworkStatus.wrongNetwork,
      );
      clearInteractions(socket);

      master.sendCommand("takePhoto", deviceId: "slave-a");
      verifyNever(() => socket.add(any()));
    });

    test("sendCommand is blocked for a slave reporting a different session",
        () async {
      SessionManager.instance.startSession(
        "master-session",
        "master-id",
        deviceType: "Master",
      );
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
        reportedSessionGuid: "different-session",
      );
      await pumpEventQueue();
      clearInteractions(socket);

      master.sendCommand("takePhoto", deviceId: "slave-a");
      verifyNever(() => socket.add(any()));
    });

    test("scheduleCommand broadcasts a scheduledCommand payload", () async {
      final socket = await registerReady("slave-a");
      final scheduledTime = DateTime.utc(2026, 6, 9, 3, 45);
      final masterTime = DateTime.utc(2026, 6, 9, 3, 44);

      master.scheduleCommand(
        "takePhoto",
        scheduledTime,
        masterTime: masterTime,
      );

      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      final decoded = jsonDecode(sent) as Map<String, dynamic>;
      expect(decoded["type"], "scheduledCommand");
      expect(decoded["command"], "takePhoto");
      expect(decoded["scheduledTime"], scheduledTime.toIso8601String());
      expect(decoded["masterTime"], masterTime.toIso8601String());
    });
  });

  group("identify command", () {
    late Directory storageRoot;
    late MasterServer master;

    setUp(() {
      storageRoot =
          Directory.systemTemp.createTempSync("master_server_identify");
      master = buildServer(storageRoot: storageRoot);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    test("sendIdentifyCommand emits identifySlave and records the request",
        () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      clearInteractions(socket);

      final requestedAt = DateTime.utc(2026, 6, 9, 3, 40);
      final result = master.sendIdentifyCommand(
        deviceId: "slave-a",
        requestId: "identify-7",
        requestedAt: requestedAt,
      );

      expect(result, isTrue);
      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      final decoded = jsonDecode(sent) as Map<String, dynamic>;
      expect(decoded["command"], "identifySlave");
      expect(decoded["requestId"], "identify-7");
      expect(decoded["requestedAt"], requestedAt.toIso8601String());

      final info = master.getConnectedDeviceInfos().single;
      expect(info.lastIdentifyRequestId, "identify-7");
      expect(info.lastIdentifyRequestedAt, requestedAt);
      expect(info.identifyStatus, "requested");
    });

    test("sendIdentifyCommand returns false for an unconnected device", () {
      expect(
        master.sendIdentifyCommand(deviceId: "ghost"),
        isFalse,
      );
    });

    test("sendIdentifyCommand is blocked for a wrong-network slave", () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: "10.0.0.5",
        networkSnapshot: snapshotFor("10.0.0.5"),
      );
      await pumpEventQueue();
      clearInteractions(socket);

      expect(master.sendIdentifyCommand(deviceId: "slave-a"), isFalse);
      verifyNever(() => socket.add(any()));
    });
  });

  group("session lifecycle broadcasts", () {
    late Directory storageRoot;
    late MasterServer master;

    setUp(() {
      storageRoot =
          Directory.systemTemp.createTempSync("master_server_session");
      master = buildServer(storageRoot: storageRoot);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    test("startNewSession activates a session and notifies slaves", () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      clearInteractions(socket);

      master.startNewSession("brand-new-session", displayName: "Court 3");

      expect(SessionManager.instance.isSessionActive, isTrue);
      expect(SessionManager.instance.sessionGuid, "brand-new-session");
      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      final decoded = jsonDecode(sent) as Map<String, dynamic>;
      expect(decoded["command"], "sessionStarted");
      expect(decoded["sessionGuid"], "brand-new-session");
      expect(decoded["displayName"], "Court 3");
    });

    test("endCurrentSession ends the session and notifies slaves", () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      master.startNewSession("ending-session");
      clearInteractions(socket);

      await master.endCurrentSession();

      expect(SessionManager.instance.isSessionActive, isFalse);
      final sent =
          verify(() => socket.add(captureAny())).captured.single as String;
      final decoded = jsonDecode(sent) as Map<String, dynamic>;
      expect(decoded["command"], "sessionEnded");
      expect(decoded["sessionGuid"], "ending-session");
    });

    test("endCurrentSession with no active session broadcasts nothing",
        () async {
      final socket = await () async {
        final s = buildMockSocket();
        await master.registerOrUpdateClientForTest(
          deviceId: "slave-a",
          socket: s,
          remoteIp: null,
          networkSnapshot: null,
        );
        await pumpEventQueue();
        clearInteractions(s);
        return s;
      }();

      await master.endCurrentSession();
      verifyNever(() => socket.add(any()));
    });
  });

  group("disconnect and reconnect handling", () {
    late Directory storageRoot;
    late MasterServer master;

    setUp(() {
      storageRoot =
          Directory.systemTemp.createTempSync("master_server_disconnect");
      master = buildServer(storageRoot: storageRoot);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    test("removing the current socket marks the client disconnected but known",
        () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );

      master.removeClientIfCurrentForTest(deviceId: "slave-a", socket: socket);

      expect(master.getConnectedDeviceIds(), isEmpty);
      final info = master.getConnectedDeviceInfos().single;
      expect(info.deviceId, "slave-a");
      expect(info.isConnected, isFalse);
      expect(info.disconnectedAt, isNotNull);
    });

    test("removing a stale socket does not evict the live connection",
        () async {
      final liveSocket = buildMockSocket();
      final staleSocket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: liveSocket,
        remoteIp: null,
        networkSnapshot: null,
      );

      // A late "onDone" from a previous socket must not remove the new one.
      master.removeClientIfCurrentForTest(
        deviceId: "slave-a",
        socket: staleSocket,
      );

      expect(master.getConnectedDeviceIds(), contains("slave-a"));
      expect(master.getConnectedDeviceInfos().single.isConnected, isTrue);
    });

    test("re-registering the same deviceId swaps the socket and reconnects",
        () async {
      final firstSocket = buildMockSocket();
      final secondSocket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: firstSocket,
        remoteIp: null,
        networkSnapshot: null,
      );
      master.removeClientIfCurrentForTest(
        deviceId: "slave-a",
        socket: firstSocket,
      );
      expect(master.getConnectedDeviceInfos().single.isConnected, isFalse);

      // Reconnect on a fresh socket.
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: secondSocket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      clearInteractions(secondSocket);
      clearInteractions(firstSocket);

      expect(master.getConnectedDeviceIds(), contains("slave-a"));
      expect(master.getConnectedDeviceInfos().single.isConnected, isTrue);

      // Commands now go to the new socket only.
      master.sendCommand("takePhoto", deviceId: "slave-a");
      verify(() => secondSocket.add("takePhoto")).called(1);
      verifyNever(() => firstSocket.add(any()));
    });

    test("sending to a client that already disconnected is a no-op", () async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: "slave-a",
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      master.removeClientIfCurrentForTest(deviceId: "slave-a", socket: socket);
      clearInteractions(socket);

      master.sendCommand("takePhoto", deviceId: "slave-a");
      verifyNever(() => socket.add(any()));
    });
  });

  group("inactivity eviction (injected clock)", () {
    late Directory storageRoot;
    late DateTime clock;
    late MasterServer master;
    late List<String> removed;

    setUp(() {
      storageRoot = Directory.systemTemp.createTempSync("master_server_evict");
      clock = DateTime.utc(2026, 6, 9, 3, 40);
      master = buildServer(storageRoot: storageRoot, now: () => clock);
      removed = <String>[];
      master.onClientRemoved = (deviceId, threshold) => removed.add(deviceId);
    });

    tearDown(() {
      storageRoot.deleteSync(recursive: true);
    });

    Future<MockWebSocket> registerAt(String deviceId) async {
      final socket = buildMockSocket();
      await master.registerOrUpdateClientForTest(
        deviceId: deviceId,
        socket: socket,
        remoteIp: null,
        networkSnapshot: null,
      );
      await pumpEventQueue();
      return socket;
    }

    test("registration timestamps come from the injected clock", () async {
      await registerAt("slave-a");
      final info = master.getConnectedDeviceInfos().single;
      expect(info.registeredAt, clock);
      expect(info.lastSeen, clock);
    });

    test(
        "a client exactly at the threshold is kept, one second past is evicted",
        () async {
      await registerAt("slave-a");

      clock = clock.add(const Duration(seconds: inactivityThreshold));
      master.sweepInactiveClientsForTest();
      expect(master.getConnectedDeviceIds(), contains("slave-a"));
      expect(removed, isEmpty);

      clock = clock.add(const Duration(seconds: 1));
      master.sweepInactiveClientsForTest();

      expect(master.getConnectedDeviceIds(), isEmpty);
      expect(removed, ["slave-a"]);
      // The device stays known, flipped to disconnected at the injected time.
      final info = master.getConnectedDeviceInfos().single;
      expect(info.deviceId, "slave-a");
      expect(info.isConnected, isFalse);
      expect(info.disconnectedAt, clock);
      expect(info.lastSeen, clock);
    });

    test("a heartbeat renews the inactivity deadline", () async {
      final socket = await registerAt("slave-a");

      clock = clock.add(const Duration(seconds: inactivityThreshold - 2));
      await master.handleIncomingMessageForTest(
        jsonEncode({"type": "heartbeat", "deviceId": "slave-a"}),
        socket: socket,
        remoteIp: null,
      );
      await pumpEventQueue();

      // Well past the original deadline, but only 2s past the heartbeat.
      clock = clock.add(const Duration(seconds: 2));
      master.sweepInactiveClientsForTest();

      expect(master.getConnectedDeviceIds(), contains("slave-a"));
      expect(removed, isEmpty);
      expect(master.getConnectedDeviceInfos().single.isConnected, isTrue);
    });

    test("the sweep evicts only the stale clients", () async {
      await registerAt("slave-stale");
      clock = clock.add(const Duration(seconds: inactivityThreshold));
      final freshSocket = await registerAt("slave-fresh");

      clock = clock.add(const Duration(seconds: 1));
      master.sweepInactiveClientsForTest();

      expect(removed, ["slave-stale"]);
      expect(master.getConnectedDeviceIds(), ["slave-fresh"]);
      // The surviving slave is still commandable.
      clearInteractions(freshSocket);
      master.sendCommand("takePhoto");
      verify(() => freshSocket.add("takePhoto")).called(1);
    });

    test("an evicted client can re-register on a fresh socket", () async {
      await registerAt("slave-a");
      clock = clock.add(const Duration(seconds: inactivityThreshold + 1));
      master.sweepInactiveClientsForTest();
      expect(master.getConnectedDeviceIds(), isEmpty);

      final secondSocket = await registerAt("slave-a");

      expect(master.getConnectedDeviceIds(), ["slave-a"]);
      final info = master.getConnectedDeviceInfos().single;
      expect(info.isConnected, isTrue);
      expect(info.lastSeen, clock);
      clearInteractions(secondSocket);
      master.sendCommand("takePhoto", deviceId: "slave-a");
      verify(() => secondSocket.add("takePhoto")).called(1);
    });
  });

  group("connected client count callback", () {
    test("onClientCountChange fires on registration and disconnect", () async {
      final storageRoot =
          Directory.systemTemp.createTempSync("master_server_count");
      final master = buildServer(storageRoot: storageRoot);
      final counts = <int>[];
      master.onClientCountChange = counts.add;
      final socket = buildMockSocket();

      try {
        await master.registerOrUpdateClientForTest(
          deviceId: "slave-a",
          socket: socket,
          remoteIp: null,
          networkSnapshot: null,
        );
        await pumpEventQueue();
        expect(counts, contains(1));

        master.removeClientIfCurrentForTest(
          deviceId: "slave-a",
          socket: socket,
        );
        expect(counts.last, 0);
      } finally {
        storageRoot.deleteSync(recursive: true);
      }
    });
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

class _FakeWebSocket extends Fake implements WebSocket {}

Future<void> _waitFor(
  bool Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail("Timed out waiting for $description.");
}
