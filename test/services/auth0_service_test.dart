import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/auth0_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test("Auth0 login requests refresh-capable scopes", () {
    expect(
      AuthService.authorizationScopes,
      containsAll(["openid", "profile", "email", "offline_access"]),
    );
  });

  test("Auth0 login persists returned credentials through secure store",
      () async {
    final expiresAt = DateTime.utc(2026, 6, 8, 20);
    final credentialStore = _RecordingAuthCredentialStore();
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: AuthLoginResponse(
          accessToken: "access-token",
          idToken: _idToken(
            email: "player@example.com",
            picture: "https://example.com/player.png",
          ),
          refreshToken: "refresh-token",
          accessTokenExpiresAt: expiresAt,
        ),
      ),
      credentialStore: credentialStore,
    );

    await authService.login();

    expect(authService.accessToken, "access-token");
    expect(authService.email, "player@example.com");
    expect(credentialStore.savedCredentials, isNotNull);
    expect(credentialStore.savedCredentials?.accessToken, "access-token");
    expect(credentialStore.savedCredentials?.idToken, isNotNull);
    expect(credentialStore.savedCredentials?.refreshToken, "refresh-token");
    expect(credentialStore.savedCredentials?.accessTokenExpiresAt, expiresAt);
  });

  test("Auth0 startup restore uses valid stored credentials", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: _idToken(
          email: "restored@example.com",
          picture: "https://example.com/restored.png",
        ),
        refreshToken: "stored-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: const AuthLoginResponse(
          accessToken: null,
          idToken: null,
          refreshToken: null,
          accessTokenExpiresAt: null,
        ),
      ),
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isTrue);
    expect(authService.accessToken, "stored-access-token");
    expect(authService.email, "restored@example.com");
    expect(authService.profilePicture, "https://example.com/restored.png");
  });

  test("Auth0 startup restore refreshes expired credentials", () async {
    final refreshedExpiresAt = DateTime.now().add(const Duration(hours: 2));
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "expired-access-token",
        idToken: _idToken(
          email: "expired@example.com",
          picture: "https://example.com/expired.png",
        ),
        refreshToken: "stored-refresh-token",
        accessTokenExpiresAt:
            DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    final authClient = _FakeAuthClient(
      response: const AuthLoginResponse(
        accessToken: null,
        idToken: null,
        refreshToken: null,
        accessTokenExpiresAt: null,
      ),
      refreshResponse: AuthLoginResponse(
        accessToken: "refreshed-access-token",
        idToken: _idToken(
          email: "refreshed@example.com",
          picture: "https://example.com/refreshed.png",
        ),
        refreshToken: "new-refresh-token",
        accessTokenExpiresAt: refreshedExpiresAt,
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isTrue);
    expect(authClient.refreshCalls, 1);
    expect(authClient.lastRefreshToken, "stored-refresh-token");
    expect(authService.accessToken, "refreshed-access-token");
    expect(authService.email, "refreshed@example.com");
    expect(authService.profilePicture, "https://example.com/refreshed.png");
    expect(credentialStore.savedCredentials?.accessToken,
        "refreshed-access-token");
    expect(credentialStore.savedCredentials?.refreshToken, "new-refresh-token");
    expect(
      credentialStore.savedCredentials?.accessTokenExpiresAt,
      refreshedExpiresAt,
    );
  });

  test("Auth0 startup restore rejects expired stored credentials", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "expired-access-token",
        idToken: _idToken(
          email: "expired@example.com",
          picture: "https://example.com/expired.png",
        ),
        refreshToken: null,
        accessTokenExpiresAt:
            DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: const AuthLoginResponse(
          accessToken: null,
          idToken: null,
          refreshToken: null,
          accessTokenExpiresAt: null,
        ),
      ),
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isFalse);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 logout clears secure credentials and browser session", () async {
    final credentialStore = _RecordingAuthCredentialStore();
    final idToken = _idToken(
      email: "logout@example.com",
      picture: "https://example.com/logout.png",
    );
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "logout-access-token",
        idToken: idToken,
        refreshToken: "logout-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    await authService.login();
    await authService.logout();

    expect(authClient.logoutCalls, 1);
    expect(authClient.lastLogoutIdToken, idToken);
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
    expect(await authService.restoreStoredSession(), isFalse);
  });

  test("Auth0 startup restore skips unsupported desktop platforms", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: _idToken(
          email: "desktop@example.com",
          picture: "https://example.com/desktop.png",
        ),
        refreshToken: "stored-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: const AuthLoginResponse(
          accessToken: null,
          idToken: null,
          refreshToken: null,
          accessTokenExpiresAt: null,
        ),
      ),
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isFalse);
    expect(credentialStore.loadCalls, 0);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 login rejects unsupported desktop platforms", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "desktop-access-token",
        idToken: _idToken(
          email: "desktop@example.com",
          picture: "https://example.com/desktop.png",
        ),
        refreshToken: "desktop-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: _RecordingAuthCredentialStore(),
    );

    await expectLater(
      authService.login(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(authClient.loginCalls, 0);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
  });
}

class _FakeAuthClient implements AuthClient {
  final AuthLoginResponse response;
  final AuthLoginResponse? refreshResponse;
  int refreshCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;
  String? lastRefreshToken;
  String? lastLogoutIdToken;

  _FakeAuthClient({required this.response, this.refreshResponse});

  @override
  Future<AuthLoginResponse> login({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
  }) async {
    loginCalls += 1;
    return response;
  }

  @override
  Future<AuthLoginResponse> refresh({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
    required String refreshToken,
  }) async {
    refreshCalls += 1;
    lastRefreshToken = refreshToken;
    return refreshResponse ?? response;
  }

  @override
  Future<void> logout({
    required String idToken,
    required String postLogoutRedirectUrl,
    required String issuer,
  }) async {
    logoutCalls += 1;
    lastLogoutIdToken = idToken;
  }
}

class _RecordingAuthCredentialStore implements AuthCredentialStore {
  AuthCredentials? savedCredentials;
  AuthCredentials? storedCredentials;
  int clearCalls = 0;
  int loadCalls = 0;

  _RecordingAuthCredentialStore({this.storedCredentials});

  @override
  Future<void> save(AuthCredentials credentials) async {
    savedCredentials = credentials;
    storedCredentials = credentials;
  }

  @override
  Future<AuthCredentials?> load() async {
    loadCalls += 1;
    return storedCredentials;
  }

  @override
  Future<void> clear() async {
    clearCalls += 1;
    savedCredentials = null;
    storedCredentials = null;
  }
}

String _idToken({required String email, required String picture}) {
  return [
    "eyJhbGciOiJub25lIn0",
    _base64UrlJson({
      "email": email,
      "picture": picture,
    }),
    "signature",
  ].join(".");
}

String _base64UrlJson(Map<String, Object?> payload) {
  final json =
      '{"email":"${payload["email"]}","picture":"${payload["picture"]}"}';
  return _base64UrlNoPadding(json);
}

String _base64UrlNoPadding(String value) {
  return base64UrlEncode(value.codeUnits).replaceAll("=", "");
}
