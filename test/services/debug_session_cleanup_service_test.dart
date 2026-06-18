import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:hydracam/services/auth0_m2m_service.dart";
import "package:hydracam/services/debug_session_cleanup_service.dart";
import "package:hydracam/services/debug_session_registry.dart";
import "package:hydracam/services/hydracam_api_service.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    M2MAuthService.overrideTokenForTests("test-token");
  });

  tearDown(() {
    HydraCamApiService.resetHttpClient();
  });

  test("deletes registered debug sessions from the service", () async {
    final requestedUris = <Uri>[];
    HydraCamApiService.configureHttpClient(
      MockClient((request) async {
        requestedUris.add(request.url);
        return http.Response("{}", 200);
      }),
    );
    final registry = DebugSessionRegistry();
    await registry.record(
      const DebugSessionRef(
        sessionGuid: "debug-guid",
        sessionId: "debug-android-20260618T123456Z",
        serviceNumericId: 456,
      ),
    );

    final deletedCount = await DebugSessionCleanupService(
      registry: registry,
      apiService: HydraCamApiService(),
    ).deleteRegisteredDebugSessions();

    expect(deletedCount, 1);
    expect(await registry.list(), isEmpty);
    expect(requestedUris.single.path, "/api/sessions/debug/delete");
    expect(
      requestedUris.single.queryParameters,
      containsPair("sessionGuid", "debug-guid"),
    );
    expect(requestedUris.single.queryParameters, containsPair("id", "456"));
  });
}
