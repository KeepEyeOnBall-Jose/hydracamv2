import "dart:async";
import "dart:io";

import "package:camera/camera.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/slave/master_discovery.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:hydracam/slave/slave_screen_controller.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

/// Fake [SlaveConnectionClient] that records the callbacks wired by the
/// controller and lets the test drive status / connection / capture events.
class FakeSlaveConnectionClient implements SlaveConnectionClient {
  FakeSlaveConnectionClient(
    this.serverAddress, {
    this.onScheduledCommand,
    this.onPhotoTaken,
    this.onRecordingStarted,
    this.onRecordingStopped,
  });

  final String serverAddress;
  final Function(String command, DateTime scheduledTime)? onScheduledCommand;
  final Function(String path)? onPhotoTaken;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;

  final statusController = StreamController<String>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  bool connected = false;
  bool disconnected = false;
  int prepareCalls = 0;
  int stopRecordingCalls = 0;

  @override
  Stream<String> get statusStream => statusController.stream;

  @override
  Stream<bool> get connectionStatusStream => connectionController.stream;

  @override
  CameraController? get cameraController => null;

  @override
  Future<void> prepareCameraPreview() async {
    prepareCalls += 1;
  }

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

  void emitConnection(bool value) => connectionController.add(value);
  void emitStatus(String message) => statusController.add(message);
  void emitRecordingStarted() => onRecordingStarted?.call();
  void emitPhotoTaken(String path) => onPhotoTaken?.call(path);

  Future<void> dispose() async {
    await statusController.close();
    await connectionController.close();
  }
}

class FakeMasterDiscovery extends MasterDiscovery {
  FakeMasterDiscovery([this.onDiscovered])
      : super(onMasterDiscovered: onDiscovered ?? (_) {});

  final void Function(String masterIp)? onDiscovered;
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

  void discover(String masterIp) => onDiscovered?.call(masterIp);
}

const NetworkReadinessResult _readyResult = NetworkReadinessResult(
  canUseLocalControl: true,
  blockingReason: NetworkReadinessBlockingReason.none,
  message: "network ready",
  snapshot: NetworkSnapshot(
    isWifiActive: true,
    ipAddress: "192.168.178.72",
    subnetMask: "255.255.255.0",
    source: "test",
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _ControllerPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  /// Builds a controller wired to fake collaborators. The returned holder's
  /// [_Harness.clients] list accumulates every fake client the controller
  /// creates; [_Harness.discovery] is populated once [start] runs.
  _Harness buildController({
    bool isAutoMode = false,
    String? preferredMasterIp,
    bool forceSlaveMode = false,
    NetworkReadinessLoader? networkReadinessLoader,
  }) {
    final harness = _Harness();
    final clients = harness.clients;

    harness.controller = SlaveScreenController(
      isAutoMode: isAutoMode,
      preferredMasterIp: preferredMasterIp,
      forceSlaveMode: forceSlaveMode,
      connectivityChanges: const Stream<List<ConnectivityResult>>.empty(),
      networkReadinessLoader:
          networkReadinessLoader ?? (() async => _readyResult),
      masterDiscoveryFactory: (onMasterDiscovered) {
        final discovery = FakeMasterDiscovery(onMasterDiscovered);
        harness.discovery = discovery;
        return discovery;
      },
      slaveClientFactory: (
        serverAddress, {
        onScheduledCommand,
        onPhotoTaken,
        onRecordingStarted,
        onRecordingStopped,
      }) {
        final client = FakeSlaveConnectionClient(
          serverAddress,
          onScheduledCommand: onScheduledCommand,
          onPhotoTaken: onPhotoTaken,
          onRecordingStarted: onRecordingStarted,
          onRecordingStopped: onRecordingStopped,
        );
        clients.add(client);
        return client;
      },
    );

    return harness;
  }

  test("discovery connect intent creates a client and marks connected",
      () async {
    final harness = buildController();
    final controller = harness.controller;
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.start();
    await pumpEventQueue();

    expect(harness.discovery.startCalls, 1);
    expect(harness.clients, isEmpty);
    expect(controller.isConnected, isFalse);

    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    expect(harness.clients, hasLength(1));
    expect(
        harness.clients.single.serverAddress, "ws://192.168.178.153:4040/ws");
    expect(harness.clients.single.connected, isTrue);
    expect(controller.isConnected, isTrue);
    expect(notifications, greaterThan(0));

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("connection drop disconnects, logs, and restarts discovery", () async {
    final harness = buildController();
    final controller = harness.controller;

    controller.start();
    await pumpEventQueue();
    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    expect(controller.isConnected, isTrue);
    final firstClient = harness.clients.single;

    firstClient.emitConnection(false);
    await pumpEventQueue();

    expect(controller.isConnected, isFalse);
    expect(firstClient.disconnected, isTrue);
    expect(
      LogService.instance.logs.map((entry) => entry["message"]),
      contains("Connection lost. Restarting discovery."),
    );
    // Reconnection restarts discovery listening.
    expect(harness.discovery.startCalls, 2);

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("rediscovery after a drop reconnects with a fresh client", () async {
    final harness = buildController();
    final controller = harness.controller;

    controller.start();
    await pumpEventQueue();
    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();
    harness.clients.single.emitConnection(false);
    await pumpEventQueue();

    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    expect(harness.clients, hasLength(2));
    expect(harness.clients.last.connected, isTrue);
    expect(controller.isConnected, isTrue);

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("recording start/stop intents propagate capture state", () async {
    final harness = buildController();
    final controller = harness.controller;
    var recordingStartedHook = 0;
    var recordingStoppedHook = 0;
    controller.onRecordingStarted = () => recordingStartedHook += 1;
    controller.onRecordingStopped = () => recordingStoppedHook += 1;

    controller.start();
    await pumpEventQueue();
    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    expect(controller.isRecording, isFalse);

    harness.clients.single.emitRecordingStarted();
    expect(controller.isRecording, isTrue);
    expect(recordingStartedHook, 1);

    await controller.stopRecordingSafely();

    expect(harness.clients.single.stopRecordingCalls, 1);
    expect(controller.isRecording, isFalse);
    expect(controller.isStoppingRecording, isFalse);
    expect(controller.statusMessage, "Recording stopped.");
    expect(recordingStoppedHook, 1);

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("status stream drives statusMessage and identify hook", () async {
    final harness = buildController();
    final controller = harness.controller;
    var identifyHook = 0;
    controller.onIdentifyAcknowledged = () => identifyHook += 1;

    controller.start();
    await pumpEventQueue();
    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    harness.clients.single.emitStatus("Taking photo...");
    await pumpEventQueue();
    expect(controller.statusMessage, "Taking photo...");
    expect(identifyHook, 0);

    harness.clients.single.emitStatus("Identify acknowledged to master.");
    await pumpEventQueue();
    expect(controller.statusMessage, "Identify acknowledged to master.");
    expect(identifyHook, 1);

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("photo capture updates status and forwards to the photo hook", () async {
    final harness = buildController();
    final controller = harness.controller;
    String? photoHookPath;
    controller.onPhotoTaken = (path) => photoHookPath = path;

    controller.start();
    await pumpEventQueue();
    harness.discovery.discover("192.168.178.153");
    await pumpEventQueue();

    harness.clients.single.emitPhotoTaken("/tmp/photo.jpg");

    expect(controller.statusMessage, "Photo taken!");
    expect(photoHookPath, "/tmp/photo.jpg");

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("fast connect skips the network readiness probe", () async {
    var readinessCalls = 0;
    final harness = buildController(
      forceSlaveMode: true,
      preferredMasterIp: "192.168.178.153",
      networkReadinessLoader: () async {
        readinessCalls += 1;
        return _readyResult;
      },
    );
    final controller = harness.controller;

    controller.start();
    await pumpEventQueue();

    expect(readinessCalls, 0);
    expect(harness.clients, hasLength(1));
    expect(
        harness.clients.single.serverAddress, "ws://192.168.178.153:4040/ws");
    expect(controller.isConnected, isTrue);

    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });

  test("session changes notify controller listeners", () async {
    final harness = buildController();
    final controller = harness.controller;
    controller.start();
    await pumpEventQueue();

    var notifications = 0;
    controller.addListener(() => notifications += 1);

    SessionManager.instance.startSession(
      "controller-session",
      "controller-session-id",
      deviceType: "Slave",
    );
    await pumpEventQueue();

    expect(notifications, greaterThan(0));
    expect(controller.photos, isEmpty);
    expect(controller.videos, isEmpty);

    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    controller.dispose();
    for (final client in harness.clients) {
      await client.dispose();
    }
  });
}

class _Harness {
  late final SlaveScreenController controller;
  final List<FakeSlaveConnectionClient> clients = <FakeSlaveConnectionClient>[];
  late final FakeMasterDiscovery discovery;
}

class _ControllerPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("slave_controller_docs");
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
