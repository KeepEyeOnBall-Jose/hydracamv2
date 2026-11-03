import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/master/master_announcer.dart";
import "package:hydracam/master/master_screen_controller.dart";
import "package:hydracam/services/battery_service.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/debug_session_policy.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/settings_service.dart";
import "package:hydracam/services/storage_service.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

class MockMasterAnnouncer extends Mock implements MasterAnnouncer {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _ControllerPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
    StorageService.configureMonitoring(enabled: false);
    BatteryService.configureMonitoring(enabled: false);
    if (!CameraServiceSingleton.isInitialized) {
      CameraServiceSingleton.initialize(
        StorageService(
          messengerState: null,
          lowStorageThreshold: 1.5,
          criticalStorageThreshold: 0.5,
          onCriticalStorageCallback: () async {},
        ),
        useMockCamera: true,
      );
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "masterShouldRecord": true,
      "timerDuration": 0,
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    SettingsService.overrideMasterShouldRecord(true);
    SettingsService.overrideTimerDuration(0);
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    pathProvider.resetDocumentsDir();
  });

  tearDown(() async {
    SettingsService.clearTestOverrides();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    pathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    StorageService.configureMonitoring(enabled: true);
    BatteryService.configureMonitoring(enabled: true);
    pathProvider.dispose();
  });

  /// A controller wired to fully-stubbed collaborators so its intent methods run
  /// without touching real sockets, the announcer, or the network.
  MockMasterServer buildStubbedServer() {
    final server = MockMasterServer();
    when(() => server.cameraService)
        .thenReturn(CameraServiceSingleton.instance);
    when(() => server.startServer()).thenAnswer((_) async {});
    when(() => server.stopServer()).thenReturn(null);
    when(() => server.startNewSession(any(),
        displayName: any(named: "displayName"))).thenReturn(null);
    when(() => server.endCurrentSession()).thenAnswer((_) async {});
    when(() => server.serverStartedAt).thenReturn(null);
    return server;
  }

  MockMasterAnnouncer buildStubbedAnnouncer() {
    final announcer = MockMasterAnnouncer();
    when(() => announcer.startBroadcasting()).thenReturn(null);
    when(() => announcer.stopBroadcasting()).thenReturn(null);
    return announcer;
  }

  test(
      "initialize starts the server and announcer and wires the count callback",
      () async {
    final server = buildStubbedServer();
    final announcer = buildStubbedAnnouncer();
    final controller = MasterScreenController(
      masterServer: server,
      announcer: announcer,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.initialize();

    verify(() => server.startServer()).called(1);
    verify(() => announcer.startBroadcasting()).called(1);

    // Capture the callback the controller installed and drive a count change.
    final countCallback =
        verify(() => server.onClientCountChange = captureAny()).captured.last
            as Function(int);
    countCallback(4);

    expect(controller.connectedClients, 4);
    expect(notifications, greaterThanOrEqualTo(1));

    controller.dispose();
  });

  test("dispose stops the server and announcer", () {
    final server = buildStubbedServer();
    final announcer = buildStubbedAnnouncer();
    final controller = MasterScreenController(
      masterServer: server,
      announcer: announcer,
    );
    controller.initialize();

    controller.dispose();

    verify(() => server.stopServer()).called(1);
    verify(() => announcer.stopBroadcasting()).called(1);
  });

  test("createSession propagates the new session to the server and manager",
      () async {
    final server = buildStubbedServer();
    final api = MockHydraCamApiService();
    when(() => api.createSession(any(),
            courtGuid: any(named: "courtGuid"),
            userGuid: any(named: "userGuid")))
        .thenAnswer((_) async => const HydraCamBackendSession(
              guid: "controller-session-guid",
              sessionId: "controller-session-id",
            ));

    final controller = MasterScreenController(
      masterServer: server,
      announcer: buildStubbedAnnouncer(),
      apiService: api,
      // Avoid debug-registry writes; exercise only session propagation.
      debugSessionPolicy: DebugSessionPolicy(debugBuild: false),
    );
    final messages = <String>[];
    controller.showMessage = (message, {duration}) => messages.add(message);

    await controller.createSession(skipCourtSelectionWarning: true);

    verify(() => server.startNewSession(
          "controller-session-guid",
          displayName: any(named: "displayName"),
        )).called(1);
    expect(SessionManager.instance.isSessionActive, isTrue);
    expect(SessionManager.instance.sessionGuid, "controller-session-guid");
    expect(controller.sessionActive, isTrue);
    expect(controller.isProcessingStartSession, isFalse);
    expect(messages, contains("Session created: ${controller.sessionDisplay}"));

    controller.dispose();
  });

  test("createSession surfaces a failure when the backend returns nothing",
      () async {
    final server = buildStubbedServer();
    final api = MockHydraCamApiService();
    when(() => api.createSession(any(),
        courtGuid: any(named: "courtGuid"),
        userGuid: any(named: "userGuid"))).thenAnswer((_) async => null);

    final controller = MasterScreenController(
      masterServer: server,
      announcer: buildStubbedAnnouncer(),
      apiService: api,
      debugSessionPolicy: DebugSessionPolicy(debugBuild: false),
    );
    final messages = <String>[];
    controller.showMessage = (message, {duration}) => messages.add(message);

    await controller.createSession(skipCourtSelectionWarning: true);

    verifyNever(() =>
        server.startNewSession(any(), displayName: any(named: "displayName")));
    expect(SessionManager.instance.isSessionActive, isFalse);
    expect(messages, contains("Failed to create session"));
    expect(controller.isProcessingStartSession, isFalse);

    controller.dispose();
  });

  test("endCurrentSession propagates the end to the server", () async {
    final server = buildStubbedServer();
    final api = MockHydraCamApiService();
    when(() => api.endSession(any())).thenAnswer((_) async => true);

    SessionManager.instance.startSession(
      "end-propagation-guid",
      "end-propagation-id",
      deviceType: "Master",
    );

    final controller = MasterScreenController(
      masterServer: server,
      announcer: buildStubbedAnnouncer(),
      apiService: api,
      debugSessionPolicy: DebugSessionPolicy(debugBuild: false),
    );
    final messages = <String>[];
    controller.showMessage = (message, {duration}) => messages.add(message);

    await controller.endCurrentSession(requireConfirmation: false);

    verify(() => api.endSession("end-propagation-guid")).called(1);
    verify(() => server.endCurrentSession()).called(1);
    expect(messages, contains("Capture session ended"));
    expect(controller.isProcessingEndSession, isFalse);

    controller.dispose();
  });

  test("client-count changes update connectedClients and notify listeners",
      () async {
    final server = buildStubbedServer();
    final controller = MasterScreenController(
      masterServer: server,
      announcer: buildStubbedAnnouncer(),
    );
    controller.initialize();

    final counts = <int>[];
    controller.addListener(() => counts.add(controller.connectedClients));

    final countCallback =
        verify(() => server.onClientCountChange = captureAny()).captured.last
            as Function(int);
    countCallback(1);
    countCallback(3);
    countCallback(0);

    expect(controller.connectedClients, 0);
    expect(counts, [1, 3, 0]);

    controller.dispose();
  });
}

class _ControllerPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("master_controller_docs");
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
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
