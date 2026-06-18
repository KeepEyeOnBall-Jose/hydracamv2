import "dart:async";
import "dart:io";

import "package:camera/camera.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/slave/master_discovery.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:hydracam/slave/slave_screen.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

class FakeSlaveConnectionClient implements SlaveConnectionClient {
  FakeSlaveConnectionClient(
    this.serverAddress, {
    this.onRecordingStarted,
    this.onRecordingStopped,
  });

  final String serverAddress;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;
  final statusController = StreamController<String>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  bool connected = false;
  bool disconnected = false;
  int stopRecordingCalls = 0;

  @override
  Stream<String> get statusStream => statusController.stream;

  @override
  Stream<bool> get connectionStatusStream => connectionController.stream;

  @override
  CameraController? get cameraController => null;

  @override
  Future<void> prepareCameraPreview() async {}

  @override
  Future<void> stopRecordingLocally() async {
    stopRecordingCalls += 1;
    onRecordingStopped?.call();
  }

  @override
  void connect() {
    connected = true;
    connectionController.add(true);
  }

  @override
  void disconnect() {
    disconnected = true;
  }

  void emitRecordingStarted() {
    onRecordingStarted?.call();
  }

  Future<void> dispose() async {
    await statusController.close();
    await connectionController.close();
  }
}

class FakeMasterDiscovery extends MasterDiscovery {
  FakeMasterDiscovery() : super(onMasterDiscovered: (_) {});

  var startCalls = 0;
  var stopCalls = 0;

  @override
  Future<void> startListening() async {
    startCalls += 1;
  }

  @override
  Future<void> stopListening() async {
    stopCalls += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _SlaveScreenPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "screenAutoOff": false,
    });
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
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

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() {
    pathProvider.dispose();
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
    expect(find.textContaining("No active session"), findsOneWidget);
    expect(find.text("Master connected"), findsOneWidget);
    expect(find.byIcon(Icons.link_outlined), findsOneWidget);
    expect(find.textContaining("Clock sync: calibrating"), findsOneWidget);
    expect(find.text("No media available"), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets("slave app bar opens uploader info directly", (tester) async {
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
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

    expect(find.byTooltip("Uploader Info"), findsOneWidget);

    await tester.tap(find.byTooltip("Uploader Info"));
    await tester.pumpAndSettle();

    expect(find.text("Photos uploaded: 0 / 0"), findsOneWidget);
    expect(find.text("Videos uploaded: 0 / 0"), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets(
      "connectivity stream errors are logged without uncaught exception",
      (tester) async {
    final connectivityController =
        StreamController<List<ConnectivityResult>>.broadcast();
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
          connectivityChanges: connectivityController.stream,
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

    connectivityController.addError(
      const SocketException("dbus unavailable"),
      StackTrace.current,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await connectivityController.close();
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets("linux skips default connectivity stream subscription",
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
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

    expect(tester.takeException(), isNull);
    expect(clients, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets("recording slave surface exposes safe stop control",
      (tester) async {
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
          slaveClientFactory: (
            serverAddress, {
            onScheduledCommand,
            onPhotoTaken,
            onRecordingStarted,
            onRecordingStopped,
          }) {
            final client = FakeSlaveConnectionClient(
              serverAddress,
              onRecordingStarted: onRecordingStarted,
              onRecordingStopped: onRecordingStopped,
            );
            clients.add(client);
            return client;
          },
        ),
      ),
    );
    await tester.pump();

    clients.single.emitRecordingStarted();
    await tester.pump();

    expect(find.text("Recording..."), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byTooltip("Stop recording safely"), findsOneWidget);

    await tester.tap(find.byTooltip("Stop recording safely"));
    await tester.pump();

    expect(clients.single.stopRecordingCalls, 1);
    expect(find.text("Prepare Camera"), findsOneWidget);
    expect(find.text("Recording..."), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets("recording slave screen auto-off dims and tap wakes",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "screenAutoOff": true,
    });
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
          slaveClientFactory: (
            serverAddress, {
            onScheduledCommand,
            onPhotoTaken,
            onRecordingStarted,
            onRecordingStopped,
          }) {
            final client = FakeSlaveConnectionClient(
              serverAddress,
              onRecordingStarted: onRecordingStarted,
              onRecordingStopped: onRecordingStopped,
            );
            clients.add(client);
            return client;
          },
        ),
      ),
    );
    await tester.pump();

    clients.single.emitRecordingStarted();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));

    expect(find.text("Screen Off - Tap to wake"), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);

    await tester.tap(find.text("Screen Off - Tap to wake"));
    await tester.pump();

    expect(find.text("Screen Off - Tap to wake"), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets("identify command acknowledgement shows visible slave frame",
      (tester) async {
    final clients = <FakeSlaveConnectionClient>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: false,
          preferredMasterIp: "192.168.178.153",
          forceSlaveMode: true,
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

    clients.single.statusController.add("Identify acknowledged to master.");
    await tester.pump();
    await tester.pump();

    expect(find.text("Identifying this slave"), findsOneWidget);
    expect(find.text("Prepare Camera"), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));

    expect(find.text("Identifying this slave"), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final client in clients) {
      await client.dispose();
    }
  });

  testWidgets(
      "auto-mode slave with active session does not promote on discovery timeout",
      (tester) async {
    final discovery = FakeMasterDiscovery();
    SessionManager.instance.startSession(
      "active-slave-session",
      "active-slave-session-id",
      deviceType: "Slave",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: true,
          connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
          masterDiscoveryFactory: (_) => discovery,
          networkReadinessLoader: () async => const NetworkReadinessResult(
            canUseLocalControl: true,
            blockingReason: NetworkReadinessBlockingReason.none,
            message: "network ready",
            snapshot: NetworkSnapshot(
              isWifiActive: true,
              ipAddress: "192.168.178.70",
              subnetMask: "255.255.255.0",
              source: "test",
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(discovery.startCalls, 1);
    expect(find.byType(SlaveScreen), findsOneWidget);
    expect(find.textContaining("No active session"), findsNothing);
    expect(
      find.textContaining("Master unavailable; preserving active session"),
      findsOneWidget,
    );
    expect(SessionManager.instance.sessionGuid, "active-slave-session");

    await tester.pumpWidget(const SizedBox.shrink());
    if (SessionManager.instance.isSessionActive) {
      await tester.runAsync(SessionManager.instance.endSession);
    }
  });

  testWidgets("auto-mode slave without active session still promotes",
      (tester) async {
    final discovery = FakeMasterDiscovery();

    await tester.pumpWidget(
      MaterialApp(
        home: SlaveScreen(
          isAutoMode: true,
          connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
          masterDiscoveryFactory: (_) => discovery,
          networkReadinessLoader: () async => const NetworkReadinessResult(
            canUseLocalControl: true,
            blockingReason: NetworkReadinessBlockingReason.none,
            message: "network ready",
            snapshot: NetworkSnapshot(
              isWifiActive: true,
              ipAddress: "192.168.178.71",
              subnetMask: "255.255.255.0",
              source: "test",
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(discovery.startCalls, 1);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("No master found, switching to Master mode."),
    );
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Cleaned up Slave mode."),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _SlaveScreenPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync("slave_screen_docs");
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
