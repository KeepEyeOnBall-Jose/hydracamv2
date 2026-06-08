import "dart:async";

import "package:camera/camera.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:hydracam/slave/slave_screen.dart";

class FakeSlaveConnectionClient implements SlaveConnectionClient {
  FakeSlaveConnectionClient(this.serverAddress);

  final String serverAddress;
  final statusController = StreamController<String>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  bool connected = false;
  bool disconnected = false;

  @override
  Stream<String> get statusStream => statusController.stream;

  @override
  Stream<bool> get connectionStatusStream => connectionController.stream;

  @override
  CameraController? get cameraController => null;

  @override
  Future<void> prepareCameraPreview() async {}

  @override
  void connect() {
    connected = true;
  }

  @override
  void disconnect() {
    disconnected = true;
  }

  Future<void> dispose() async {
    await statusController.close();
    await connectionController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
  });

  testWidgets(
      "forced preferred master connects without network readiness probe",
      (tester) async {
    var readinessCalls = 0;
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
          networkReadinessLoader: () async {
            readinessCalls += 1;
            return NetworkReadinessResult(
              canUseLocalControl: false,
              blockingReason: NetworkReadinessBlockingReason.wifiDisabled,
              message: "network readiness should not be checked",
              snapshot: const NetworkSnapshot(
                isWifiActive: false,
                source: "test",
              ),
            );
          },
          slaveClientFactory: (
            serverAddress, {
            onScheduledCommand,
            onPhotoTaken,
            onRecordingStarted,
            onRecordingStopped,
          }) {
            final client = FakeSlaveConnectionClient(serverAddress);
            clients.add(client);
            return client;
          },
        ),
      ),
    );

    await tester.pump();

    expect(readinessCalls, 0);
    expect(clients, hasLength(1));
    expect(clients.single.serverAddress, "ws://192.168.178.153:4040/ws");
    expect(clients.single.connected, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });
}
