import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_appauth/flutter_appauth.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/auth0_service.dart";

void main() {
  test("rejected identity clears memory even when credential deletion fails",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final store = _RecordingAuthCredentialStore()
      ..clearError = StateError("locked store");
    final auth = AuthService(
        credentialStore: store,
        authClient: _FakeAuthClient(
            response: AuthLoginResponse(
          accessToken: "unit-test-access",
          idToken:
              _idTokenFromPayload({"email": "player@example.com", "sub": ""}),
          refreshToken: "unit-test-refresh",
          accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        )));
    await expectLater(auth.login(), throwsA(anything));
    expect(auth.email, isNull);
    expect(auth.accessToken, isNull);
  });
  TestWidgetsFlutterBinding.ensureInitialized();

  AuthCredentials expiredCredentials() => AuthCredentials(
        accessToken: "expired-test-access",
        idToken: _idToken(email: "player@example.com", picture: ""),
        refreshToken: "stored-test-refresh",
        accessTokenExpiresAt:
            DateTime.now().subtract(const Duration(minutes: 1)),
      );
  AuthLoginResponse freshResponse() => AuthLoginResponse(
        accessToken: "renewed-test-access",
        idToken: _idToken(email: "player@example.com", picture: ""),
        refreshToken: "rotated-test-refresh",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  test("concurrent restores exchange a rotating refresh token once", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse())
      ..refreshPending = Completer<AuthLoginResponse>();
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials());
    final auth = AuthService(authClient: client, credentialStore: store);
    final first = auth.restoreStoredSession();
    final second = auth.restoreStoredSession();
    await Future<void>.delayed(Duration.zero);
    expect(client.refreshCalls, 1);
    client.refreshPending!.complete(freshResponse());
    expect(await Future.wait([first, second]), [true, true]);
    expect(store.storedCredentials?.refreshToken, "rotated-test-refresh");
  });

  test("offline refresh retains credentials and a later attempt recovers",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse())
      ..refreshError = TimeoutException("network unavailable");
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials());
    final auth = AuthService(authClient: client, credentialStore: store);
    expect(await auth.restoreStoredSession(), false);
    expect(store.clearCalls, 0);
    expect(auth.accessToken, isNull);
    client.refreshError = null;
    expect(await auth.restoreStoredSession(), false);
    expect(client.refreshCalls, 1);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await auth.restoreStoredSession(), true);
  });

  test("logout fences an in-flight refresh and cannot resurrect credentials",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse())
      ..refreshPending = Completer<AuthLoginResponse>();
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials());
    final auth = AuthService(authClient: client, credentialStore: store);
    final pending = auth.restoreStoredSession();
    await Future<void>.delayed(Duration.zero);
    await auth.logout();
    client.refreshPending!.complete(freshResponse());
    expect(await pending, false);
    expect(store.storedCredentials, isNull);
    expect(auth.accessToken, isNull);
  });

  test("revoked refresh token clears credentials without exposing SDK errors",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse())
      ..refreshError = FlutterAppAuthPlatformException(
        code: "token_failed",
        platformErrorDetails:
            FlutterAppAuthPlatformErrorDetails(error: "invalid_grant"),
      );
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials());
    final auth = AuthService(authClient: client, credentialStore: store);
    expect(await auth.restoreStoredSession(), false);
    expect(store.storedCredentials, isNull);
  });

  test("rotated credentials retry persistence without another token exchange",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse());
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials())
          ..saveError = StateError("keychain temporarily unavailable");
    final auth = AuthService(authClient: client, credentialStore: store);
    expect(await auth.restoreStoredSession(), false);
    store.saveError = null;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await auth.restoreStoredSession(), true);
    expect(client.refreshCalls, 1);
    expect(store.storedCredentials?.refreshToken, "rotated-test-refresh");
  });

  test("refresh cannot switch subject even when email matches", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(
        response: AuthLoginResponse(
      accessToken: "other-test-access",
      idToken: _idTokenFromPayload({
        "iss": "https://keepeyeonball.eu.auth0.com/",
        "sub": "different-test-subject",
        "email": "player@example.com",
      }),
      refreshToken: "other-test-refresh",
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    ));
    final store =
        _RecordingAuthCredentialStore(storedCredentials: expiredCredentials());
    final auth = AuthService(authClient: client, credentialStore: store);
    expect(await auth.restoreStoredSession(), false);
    expect(auth.email, isNull);
    expect(store.storedCredentials, isNull);
  });

  test("cancelled login preserves the previously accepted credentials",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _FakeAuthClient(response: freshResponse());
    final store = _RecordingAuthCredentialStore();
    final auth = AuthService(authClient: client, credentialStore: store);
    await auth.login();
    client.loginError = FlutterAppAuthUserCancelledException(
      code: "cancelled",
      platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
    );
    await expectLater(
        auth.login(), throwsA(isA<FlutterAppAuthUserCancelledException>()));
    expect(store.storedCredentials?.refreshToken, "rotated-test-refresh");
    expect(auth.email, "player@example.com");
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test("Auth0 login requests refresh-capable scopes", () {
    expect(
      AuthService.authorizationScopes,
      containsAll(["openid", "profile", "email", "offline_access"]),
    );
  });

  test("Auth0 login uses Android package redirect URI", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "android-access-token",
        idToken: _idToken(
          email: "android@example.com",
          picture: "https://example.com/android.png",
        ),
        refreshToken: "android-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: _RecordingAuthCredentialStore(),
    );

    await authService.login();

    expect(
      authClient.lastLoginRedirectUrl,
      "com.amaia23.hydracam://login-callback",
    );
  });

  test("Auth0 login uses iOS bundle redirect URI", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "ios-access-token",
        idToken: _idToken(
          email: "ios@example.com",
          picture: "https://example.com/ios.png",
        ),
        refreshToken: "ios-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: _RecordingAuthCredentialStore(),
    );

    await authService.login();

    expect(
      authClient.lastLoginRedirectUrl,
      "com.keepeyeonball://login-callback",
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

  test("Auth0 login trims returned email claim", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final credentialStore = _RecordingAuthCredentialStore();
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: AuthLoginResponse(
          accessToken: "access-token",
          idToken: _idToken(
            email: "  player@example.com  ",
            picture: "https://example.com/player.png",
          ),
          refreshToken: "refresh-token",
          accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      credentialStore: credentialStore,
    );

    await authService.login();

    expect(authService.email, "player@example.com");
  });

  test("Auth0 login rejects returned credentials without email", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stale-access-token",
        idToken: _idToken(
          email: "stale@example.com",
          picture: "https://example.com/stale.png",
        ),
        refreshToken: "stale-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "no-email-access-token",
        idToken: _idTokenWithoutEmail(
          picture: "https://example.com/no-email-login.png",
        ),
        refreshToken: "no-email-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    await expectLater(
      authService.login(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("email claim"),
        ),
      ),
    );

    expect(authClient.loginCalls, 1);
    expect(credentialStore.clearCalls, 1);
    expect(credentialStore.savedCredentials, isNull);
    expect(credentialStore.storedCredentials, isNull);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 login failure clears stale session state", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final credentialStore = _RecordingAuthCredentialStore();
    final authClient = _FakeAuthClient(
      response: AuthLoginResponse(
        accessToken: "stale-access-token",
        idToken: _idToken(
          email: "stale@example.com",
          picture: "https://example.com/stale.png",
        ),
        refreshToken: "stale-refresh-token",
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    await authService.login();

    expect(authService.accessToken, "stale-access-token");
    expect(authService.email, "stale@example.com");

    authClient.loginError = StateError("browser login failed");

    await expectLater(
      authService.login(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("Failed to log in. Please try again."),
        ),
      ),
    );

    expect(authClient.loginCalls, 2);
    expect(credentialStore.clearCalls, 1);
    expect(credentialStore.savedCredentials, isNull);
    expect(credentialStore.storedCredentials, isNull);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
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

  test("Auth0 startup restore trims stored email claim", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: _idToken(
          email: "  restored@example.com  ",
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
    expect(authService.email, "restored@example.com");
  });

  test("Auth0 startup restore ignores non-string optional picture claim",
      () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: _idTokenFromPayload({
          "email": "restored@example.com",
          "picture": 123,
        }),
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
    expect(credentialStore.clearCalls, 0);
    expect(authService.accessToken, "stored-access-token");
    expect(authService.email, "restored@example.com");
    expect(authService.profilePicture, isNull);
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
    expect(
      authClient.lastRefreshRedirectUrl,
      "com.amaia23.hydracam://login-callback",
    );
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

  test("Auth0 startup restore clears stale credentials after failed refresh",
      () async {
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
    final authService = AuthService(
      authClient: _FakeAuthClient(
        response: const AuthLoginResponse(
          accessToken: null,
          idToken: null,
          refreshToken: null,
          accessTokenExpiresAt: null,
        ),
        refreshResponse: AuthLoginResponse(
          accessToken: null,
          idToken: _idToken(
            email: "refreshed@example.com",
            picture: "https://example.com/refreshed.png",
          ),
          refreshToken: "new-refresh-token",
          accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isFalse);
    expect(credentialStore.clearCalls, 1);
    expect(credentialStore.storedCredentials, isNull);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
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
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 startup restore rejects blank stored access token", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "   ",
        idToken: _idToken(
          email: "stored@example.com",
          picture: "https://example.com/stored.png",
        ),
        refreshToken: null,
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final authClient = _FakeAuthClient(
      response: const AuthLoginResponse(
        accessToken: null,
        idToken: null,
        refreshToken: null,
        accessTokenExpiresAt: null,
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isFalse);
    expect(authClient.refreshCalls, 0);
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 startup restore ignores blank refresh token", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "expired-access-token",
        idToken: _idToken(
          email: "expired@example.com",
          picture: "https://example.com/expired.png",
        ),
        refreshToken: "   ",
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
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    final restored = await authService.restoreStoredSession();

    expect(restored, isFalse);
    expect(authClient.refreshCalls, 0);
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 startup restore rejects stored credentials without email",
      () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: _idTokenWithoutEmail(
          picture: "https://example.com/no-email.png",
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
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });

  test("Auth0 startup restore clears malformed stored credentials", () async {
    final credentialStore = _RecordingAuthCredentialStore(
      storedCredentials: AuthCredentials(
        accessToken: "stored-access-token",
        idToken: "header.%%%%.signature",
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
    expect(credentialStore.clearCalls, 1);
    expect(credentialStore.storedCredentials, isNull);
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
    expect(
      authClient.lastLogoutRedirectUrl,
      "com.amaia23.hydracam://login-callback",
    );
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

  test(
      "Auth0 logout clears stored credentials on unsupported desktop platforms",
      () async {
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
    final authClient = _FakeAuthClient(
      response: const AuthLoginResponse(
        accessToken: null,
        idToken: null,
        refreshToken: null,
        accessTokenExpiresAt: null,
      ),
    );
    final authService = AuthService(
      authClient: authClient,
      credentialStore: credentialStore,
    );

    await authService.logout();

    expect(authClient.logoutCalls, 0);
    expect(credentialStore.clearCalls, 1);
    expect(authService.accessToken, isNull);
    expect(authService.email, isNull);
    expect(authService.profilePicture, isNull);
  });
}

class _FakeAuthClient implements AuthClient {
  final AuthLoginResponse response;
  final AuthLoginResponse? refreshResponse;
  Object? loginError;
  Object? refreshError;
  Completer<AuthLoginResponse>? refreshPending;
  int refreshCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;
  String? lastLoginRedirectUrl;
  String? lastRefreshRedirectUrl;
  String? lastRefreshToken;
  String? lastLogoutIdToken;
  String? lastLogoutRedirectUrl;

  _FakeAuthClient({required this.response, this.refreshResponse});

  @override
  Future<AuthLoginResponse> login({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
  }) async {
    loginCalls += 1;
    lastLoginRedirectUrl = redirectUrl;
    final error = loginError;
    if (error != null) {
      throw error;
    }
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
    lastRefreshRedirectUrl = redirectUrl;
    lastRefreshToken = refreshToken;
    if (refreshError != null) throw refreshError!;
    if (refreshPending != null) return refreshPending!.future;
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
    lastLogoutRedirectUrl = postLogoutRedirectUrl;
  }
}

class _RecordingAuthCredentialStore implements AuthCredentialStore {
  Object? saveError;
  Object? clearError;
  AuthCredentials? savedCredentials;
  AuthCredentials? storedCredentials;
  int clearCalls = 0;
  int loadCalls = 0;

  _RecordingAuthCredentialStore({this.storedCredentials});

  @override
  Future<void> save(AuthCredentials credentials) async {
    if (saveError != null) throw saveError!;
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
    if (clearError != null) throw clearError!;
    savedCredentials = null;
    storedCredentials = null;
  }
}

String _idToken({required String email, required String picture}) {
  return [
    "eyJhbGciOiJub25lIn0",
    _base64UrlJson({
      "iss": "https://keepeyeonball.eu.auth0.com/",
      "sub": "unit-test-subject",
      "email": email,
      "picture": picture,
    }),
    "signature",
  ].join(".");
}

String _idTokenWithoutEmail({required String picture}) {
  return [
    "eyJhbGciOiJub25lIn0",
    _base64UrlNoPadding('{"picture":"$picture"}'),
    "signature",
  ].join(".");
}

String _idTokenFromPayload(Map<String, Object?> payload) {
  return [
    "eyJhbGciOiJub25lIn0",
    _base64UrlNoPadding(jsonEncode({
      "iss": "https://keepeyeonball.eu.auth0.com/",
      "sub": "unit-test-subject",
      ...payload,
    })),
    "signature",
  ].join(".");
}

String _base64UrlJson(Map<String, Object?> payload) {
  return _base64UrlNoPadding(jsonEncode(payload));
}

String _base64UrlNoPadding(String value) {
  return base64UrlEncode(value.codeUnits).replaceAll("=", "");
}
