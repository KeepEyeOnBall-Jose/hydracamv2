import "dart:async";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

import "package:hydracam/master/master_server.dart";
import "package:hydracam/services/network_info_service.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

void main() {
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
        source: "slave-test",
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

    server.removeClientIfCurrentForTest(
      deviceId: "slave-a",
      socket: secondSocket,
    );

    expect(server.getConnectedDeviceInfos(), isEmpty);
  });
}
