import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/master/master_announcer.dart";
import "package:hydracam/master/master_screen.dart";
import "package:hydracam/screens/camera_setup_preview_screen.dart";
import "package:hydracam/screens/master_video_recording_screen.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/battery_service.dart";
import "package:hydracam/services/camera_service_singleton.dart";
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

  final pathProvider = _MasterScreenPathProvider();

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
    M2MAuthService.overrideTokenForTests("test-token");
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
    HydraCamApiService.resetHttpClient();
    SettingsService.clearTestOverrides();
    await _disposeMasterScreenSession();
    pathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    StorageService.configureMonitoring(enabled: true);
    BatteryService.configureMonitoring(enabled: true);
    pathProvider.dispose();
  });

  testWidgets("start session button creates backend session", (tester) async {
    Uri? requestedUri;
    Map<String, dynamic>? requestBody;
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"guid":"master-screen-guid","sessionId":"master-session-id"}',
          200,
        );
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MasterScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, "Start Session"));
    await tester.pumpAndSettle();

    expect(SessionManager.instance.sessionGuid, "master-screen-guid");
    expect(
      SessionManager.instance.currentSession?.sessionId,
      "master-session-id",
    );
    expect(requestedUri?.path, "/api/sessions/create");
    expect(requestBody?["SessionId"], isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("disposing master screen does not end active session",
      (tester) async {
    final masterServer = MockMasterServer();
    final announcer = MockMasterAnnouncer();
    when(() => masterServer.cameraService)
        .thenReturn(CameraServiceSingleton.instance);
    when(() => masterServer.getConnectedDeviceInfos()).thenReturn([]);
    when(() => masterServer.getConnectedDeviceIds()).thenReturn([]);
    when(() => masterServer.startServer()).thenAnswer((_) async {});
    when(() => masterServer.stopServer()).thenReturn(null);
    when(() => announcer.startBroadcasting()).thenReturn(null);
    when(() => announcer.stopBroadcasting()).thenReturn(null);
    await tester.pumpWidget(
      MaterialApp(
        home: MasterScreen(
          masterServer: masterServer,
          announcer: announcer,
        ),
      ),
    );
    await tester.pump();

    SessionManager.instance.startSession(
      "dispose-contract-guid",
      "dispose-contract-session-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(SessionManager.instance.isSessionActive, isTrue);
    expect(SessionManager.instance.sessionGuid, "dispose-contract-guid");

    await tester.runAsync(SessionManager.instance.endSession);

    expect(SessionManager.instance.isSessionActive, isFalse);
    verify(() => masterServer.startServer()).called(1);
    verify(() => masterServer.stopServer()).called(1);
    verify(() => announcer.startBroadcasting()).called(1);
    verify(() => announcer.stopBroadcasting()).called(1);
  });

  testWidgets("recording start path opens master video preview",
      (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        return http.Response(
          '{"guid":"recording-preview-guid","sessionId":"recording-preview-id"}',
          200,
        );
      }),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MasterScreen(),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, "Start Session"));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, "Start Recording"));
    await tester.pumpAndSettle();

    expect(find.text("Prepare Camera"), findsOneWidget);

    final previewStartButton = find.descendant(
      of: find.byType(CameraSetupPreviewContent),
      matching: find.widgetWithText(ElevatedButton, "Start Recording"),
    );
    final button = tester.widget<ElevatedButton>(previewStartButton);
    button.onPressed?.call();
    for (var i = 0;
        i < 20 && find.byType(MasterVideoRecordingScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(MasterVideoRecordingScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _disposeMasterScreenSession() async {
  if (SessionManager.instance.isSessionActive) {
    await SessionManager.instance.endSession();
  }
}

class _MasterScreenPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync("master_screen_docs");
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
