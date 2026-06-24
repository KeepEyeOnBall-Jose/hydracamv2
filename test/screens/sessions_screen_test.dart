import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/screens/sessions_screen.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/session_manager.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _SessionsPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    M2MAuthService.overrideTokenForTests("test-token");
    LogService.instance.clearLogs();
  });

  tearDown(() async {
    HydraCamApiService.resetHttpClient();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    pathProvider.resetDocumentsDir();
    LogService.instance.clearLogs();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  testWidgets("backend sessions list uses readable title as primary label",
      (tester) async {
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        expect(request.method, "GET");
        expect(request.url.path, "/api/sessions");
        expect(request.url.queryParameters["courtGuid"], "court-guid");
        return http.Response(
          jsonEncode([
            {
              "guid": "backend-session-guid",
              "sessionId": "legacy-session-id",
              "displayName": "Squash match - Sportwerk Court 2",
              "startTime": "2026-06-09T01:00:00Z",
              "endTime": "2026-06-09T02:00:00Z",
            },
          ]),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(courtGuid: "court-guid"),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.text("Session: Squash match - Sportwerk Court 2"), findsOneWidget);
    expect(find.text("Service GUID: backend-session-guid"), findsOneWidget);
    expect(find.text("Legacy Session ID: legacy-session-id"), findsOneWidget);
    expect(find.text("Session: backend-session-guid"), findsNothing);
    expect(find.text("legacy-session-id"), findsNothing);
  });

  testWidgets("loading backend session reports guid as selected session",
      (tester) async {
    HydraCamApiService.configureHttpClient(_backendSessionListClient());

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          "/": (context) => const Scaffold(body: Text("Master Screen")),
          "/sports": (context) => const Scaffold(body: Text("Sports Centers")),
          "/courts": (context) => const Scaffold(body: Text("Courts")),
          "/sessions": (context) => SessionsScreen(courtGuid: "court-guid"),
        },
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushNamed("/sports"));
    await tester.pumpAndSettle();
    unawaited(navigator.pushNamed("/courts"));
    await tester.pumpAndSettle();
    unawaited(navigator.pushNamed("/sessions"));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();

    expect(SessionManager.instance.sessionGuid, "backend-session-guid");
    expect(
      SessionManager.instance.currentSession?.sessionId,
      "legacy-session-id",
    );
    expect(
      SessionManager.instance.currentSession?.displayName,
      "Squash match - Sportwerk Court 2",
    );
    expect(find.text("Session loaded: Squash match - Sportwerk Court 2"),
        findsOneWidget);
    expect(find.text("Master Screen"), findsOneWidget);
  });
}

class _SessionsPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync(
      "sessions_screen_docs",
    );
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

MockClient _backendSessionListClient() {
  return MockClient((request) async {
    expect(request.method, "GET");
    expect(request.url.path, "/api/sessions");
    expect(request.url.queryParameters["courtGuid"], "court-guid");
    return http.Response(
      jsonEncode([
        {
          "guid": "backend-session-guid",
          "sessionId": "legacy-session-id",
          "displayName": "Squash match - Sportwerk Court 2",
          "startTime": "2026-06-09T01:00:00Z",
          "endTime": "2026-06-09T02:00:00Z",
        },
      ]),
      200,
    );
  });
}
