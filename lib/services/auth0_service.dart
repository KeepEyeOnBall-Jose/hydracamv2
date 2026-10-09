import "dart:convert";
import "package:flutter/foundation.dart";
import "package:flutter_appauth/flutter_appauth.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "log_service.dart";

class AuthLoginResponse {
  final String? accessToken;
  final String? idToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;

  const AuthLoginResponse({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });
}

class AuthCredentials {
  final String? accessToken;
  final String? idToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;

  const AuthCredentials({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
  });
}

abstract class AuthClient {
  Future<AuthLoginResponse> login({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
  });

  Future<AuthLoginResponse> refresh({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
    required String refreshToken,
  });

  Future<void> logout({
    required String idToken,
    required String postLogoutRedirectUrl,
    required String issuer,
  });
}

abstract class AuthCredentialStore {
  Future<void> save(AuthCredentials credentials);

  Future<AuthCredentials?> load();

  Future<void> clear();
}

class FlutterAppAuthClient implements AuthClient {
  final FlutterAppAuth _appAuth;

  const FlutterAppAuthClient({FlutterAppAuth appAuth = const FlutterAppAuth()})
      : _appAuth = appAuth;

  @override
  Future<AuthLoginResponse> login({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
  }) async {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUrl,
        issuer: issuer,
        scopes: scopes,
      ),
    );
    return AuthLoginResponse(
      accessToken: result.accessToken,
      idToken: result.idToken,
      refreshToken: result.refreshToken,
      accessTokenExpiresAt: result.accessTokenExpirationDateTime,
    );
  }

  @override
  Future<AuthLoginResponse> refresh({
    required String clientId,
    required String redirectUrl,
    required String issuer,
    required List<String> scopes,
    required String refreshToken,
  }) async {
    final result = await _appAuth.token(
      TokenRequest(
        clientId,
        redirectUrl,
        issuer: issuer,
        scopes: scopes,
        refreshToken: refreshToken,
      ),
    );
    return AuthLoginResponse(
      accessToken: result.accessToken,
      idToken: result.idToken,
      refreshToken: result.refreshToken,
      accessTokenExpiresAt: result.accessTokenExpirationDateTime,
    );
  }

  @override
  Future<void> logout({
    required String idToken,
    required String postLogoutRedirectUrl,
    required String issuer,
  }) async {
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idToken,
        postLogoutRedirectUrl: postLogoutRedirectUrl,
        issuer: issuer,
      ),
    );
  }
}

class SecureAuthCredentialStore implements AuthCredentialStore {
  static const String _credentialsKey = "auth0_credentials_v1";
  static const String _accessTokenKey = "auth0_access_token";
  static const String _idTokenKey = "auth0_id_token";
  static const String _refreshTokenKey = "auth0_refresh_token";
  static const String _expiresAtKey = "auth0_access_token_expires_at";

  final FlutterSecureStorage _storage;

  const SecureAuthCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<void> save(AuthCredentials credentials) async {
    // One secure-store replacement: a rotated refresh token must never be
    // paired with a previous access token after interrupted multi-key writes.
    await _storage.write(
        key: _credentialsKey,
        value: jsonEncode({
          "accessToken": credentials.accessToken,
          "idToken": credentials.idToken,
          "refreshToken": credentials.refreshToken,
          "expiresAt": credentials.accessTokenExpiresAt?.toIso8601String(),
        }));
    await _clearLegacy();
  }

  @override
  Future<AuthCredentials?> load() async {
    final envelope = await _storage.read(key: _credentialsKey);
    if (envelope != null) {
      final value = jsonDecode(envelope) as Map<String, dynamic>;
      return AuthCredentials(
        accessToken: value["accessToken"] as String?,
        idToken: value["idToken"] as String?,
        refreshToken: value["refreshToken"] as String?,
        accessTokenExpiresAt:
            DateTime.tryParse(value["expiresAt"] as String? ?? ""),
      );
    }
    final accessToken = await _storage.read(key: _accessTokenKey);
    final idToken = await _storage.read(key: _idTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final expiresAtValue = await _storage.read(key: _expiresAtKey);

    if (accessToken == null &&
        idToken == null &&
        refreshToken == null &&
        expiresAtValue == null) {
      return null;
    }

    return AuthCredentials(
      accessToken: accessToken,
      idToken: idToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt:
          expiresAtValue != null ? DateTime.tryParse(expiresAtValue) : null,
    );
  }

  @override
  Future<void> clear() async {
    // Clear legacy first: a crash must not make load fall back to an older user.
    await _clearLegacy();
    await _storage.delete(key: _credentialsKey);
  }

  Future<void> _clearLegacy() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _idTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
  }
}

class AuthService {
  final AuthClient _authClient;
  final AuthCredentialStore _credentialStore;
  Future<bool>? _restoration;
  Future<void> _credentialWrites = Future<void>.value();
  int _generation = 0;
  bool _loggingOut = false;
  AuthCredentials? _pendingRotation;
  DateTime? _retryAfter;
  final Duration retryDelay;

  Future<void> _writeCredentials(Future<void> Function() action) {
    final next = _credentialWrites.then((_) => action());
    _credentialWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _clearFor(int generation) async {
    try {
      await _writeCredentials(() async {
        if (generation == _generation) await _credentialStore.clear();
      });
    } finally {
      // A locked keychain must never keep a rejected identity usable in memory.
      if (generation == _generation) _clearInMemorySession();
    }
  }

  AuthService({
    AuthClient authClient = const FlutterAppAuthClient(),
    AuthCredentialStore credentialStore = const SecureAuthCredentialStore(),
    this.retryDelay = const Duration(seconds: 2),
  })  : _authClient = authClient,
        _credentialStore = credentialStore;

  static const List<String> authorizationScopes = [
    "openid",
    "profile",
    "email",
    "offline_access",
  ];

  static const String iosRedirectScheme = String.fromEnvironment(
      "HYDRACAM_IOS_AUTH_REDIRECT_SCHEME",
      defaultValue: "com.keepeyeonball");
  static const String androidRedirectScheme = String.fromEnvironment(
      "HYDRACAM_ANDROID_AUTH_REDIRECT_SCHEME",
      defaultValue: "com.amaia23.hydracam");
  static const String authRedirectHost = "login-callback";
  static const String _missingEmailClaimMessage =
      "Auth0 ID token did not include an email claim.";

  final String _clientId = "wChCAH6ZES2UU8sGKRDjgN7JEETblQKf";
  final String _issuer = "https://keepeyeonball.eu.auth0.com";

  // Store access token and email
  String? _accessToken;
  String? _idToken;
  String? _email;
  String? _profilePicture;

  String? get accessToken => _accessToken;
  String? get email => _email;
  String? get identity => _identityFromToken(_idToken);

  String? get profilePicture => _profilePicture;

  String get _redirectScheme {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return iosRedirectScheme;
      case TargetPlatform.android:
        return androidRedirectScheme;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return androidRedirectScheme;
    }
  }

  String get _redirectUrl => "$_redirectScheme://$authRedirectHost";

  String get _postLogoutRedirectUrl => _redirectUrl;

  Future<void> login() async {
    if (_loggingOut) throw StateError("Logout is still in progress.");
    if (!_isMobileAuthPlatform) {
      _clearInMemorySession();
      throw UnsupportedError(
        "Auth0 interactive login is only supported on Android and iOS.",
      );
    }

    final generation = ++_generation;
    _retryAfter = null;
    _pendingRotation = null;
    var clearedRejectedCredentials = false;
    try {
      final result = await _authClient.login(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
        issuer: _issuer,
        scopes: authorizationScopes,
      );

      final credentials = AuthCredentials(
        accessToken: result.accessToken,
        idToken: result.idToken,
        refreshToken: result.refreshToken,
        accessTokenExpiresAt: result.accessTokenExpiresAt,
      );
      if (generation != _generation) return;
      _applyCredentials(credentials);
      if (!_hasEmailClaim || identity == null) {
        await _rejectCredentialsWithoutEmail(
            function: "login", generation: generation);
        clearedRejectedCredentials = true;
        throw const FormatException(_missingEmailClaimMessage);
      }

      await _writeCredentials(() async {
        if (generation == _generation) await _credentialStore.save(credentials);
      });

      LogService.instance.registerLog("Profile set: $_profilePicture",
          function: "login", file: "auth0_service.dart");
    } catch (e) {
      if (generation != _generation) return;
      // Closing Universal Login is not revocation of the existing session.
      if (e is FlutterAppAuthUserCancelledException) rethrow;
      if (!clearedRejectedCredentials) {
        await _clearFor(generation);
      }
      if (e is FormatException) {
        throw const FormatException(_missingEmailClaimMessage);
      }
      throw Exception("Failed to log in. Please try again.");
    }
  }

  Future<void> logout() async {
    ++_generation;
    _restoration = null;
    _pendingRotation = null;
    _retryAfter = null;
    _loggingOut = true;
    try {
      await _logout();
    } finally {
      _loggingOut = false;
    }
  }

  Future<void> _logout() async {
    if (!_isMobileAuthPlatform) {
      try {
        await _writeCredentials(_credentialStore.clear);
      } finally {
        _clearInMemorySession();
        LogService.instance.registerLog(
            "Cleared stored Auth0 session on unsupported platform.",
            function: "logout",
            file: "auth0_service.dart");
      }
      return;
    }

    var idToken = _idToken;
    _clearInMemorySession();
    try {
      idToken ??= (await _credentialStore.load())?.idToken;
    } catch (_) {
      // A failed read must not prevent attempted local logout.
    }
    await _writeCredentials(_credentialStore.clear);

    try {
      if (idToken != null) {
        await _authClient.logout(
          idToken: idToken,
          postLogoutRedirectUrl: _postLogoutRedirectUrl,
          issuer: _issuer,
        );
      }
    } finally {
      _clearInMemorySession();
      LogService.instance.registerLog("Cleared Auth0 session.",
          function: "logout", file: "auth0_service.dart");
    }
  }

  Future<bool> restoreStoredSession() {
    if (_loggingOut) return Future.value(false);
    if (_retryAfter?.isAfter(DateTime.now()) == true) {
      return Future.value(false);
    }
    final existing = _restoration;
    if (existing != null) return existing;
    late final Future<bool> pending;
    pending = _restoreStoredSession(_generation).whenComplete(() {
      if (identical(_restoration, pending)) _restoration = null;
    });
    return _restoration = pending;
  }

  Future<bool> _restoreStoredSession(int generation) async {
    if (!_isMobileAuthPlatform) {
      _clearInMemorySession();
      LogService.instance.registerLog(
          "Skipped Auth0 restore on unsupported platform.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return false;
    }

    final pending = _pendingRotation;
    if (pending != null) {
      try {
        await _writeCredentials(() async {
          if (generation == _generation) await _credentialStore.save(pending);
        });
        if (generation != _generation) return false;
        _pendingRotation = null;
      } catch (_) {
        return false;
      }
    }
    final credentials = pending ?? await _credentialStore.load();
    if (generation != _generation) return false;
    if (_canRestore(credentials)) {
      if (!await _applyStoredCredentials(credentials!, generation)) {
        return false;
      }
      LogService.instance.registerLog(
          "Restored Auth0 session from secure store.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return true;
    }

    if (_canRefresh(credentials)) {
      return _refreshStoredSession(credentials!, generation);
    }

    if (credentials != null) {
      await _clearFor(generation);
    }
    if (generation == _generation) _clearInMemorySession();
    return false;
  }

  bool _canRestore(AuthCredentials? credentials) {
    if (!_hasCredentialValue(credentials?.accessToken) ||
        !_hasCredentialValue(credentials?.idToken)) {
      return false;
    }
    final expiresAt = credentials?.accessTokenExpiresAt;
    if (expiresAt == null) {
      return false;
    }
    return expiresAt.isAfter(DateTime.now());
  }

  bool _canRefresh(AuthCredentials? credentials) {
    return _hasCredentialValue(credentials?.refreshToken);
  }

  bool _hasCredentialValue(String? value) => value?.trim().isNotEmpty ?? false;

  Future<bool> _refreshStoredSession(
      AuthCredentials credentials, int generation) async {
    try {
      final result = await _authClient.refresh(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
        issuer: _issuer,
        scopes: authorizationScopes,
        refreshToken: credentials.refreshToken!,
      );
      final refreshedCredentials = _mergeRefreshedCredentials(
        credentials,
        result,
      );
      if (generation != _generation) return false;
      final previousIdentity = _identityFromToken(credentials.idToken);
      if (previousIdentity == null ||
          _identityFromToken(refreshedCredentials.idToken) !=
              previousIdentity) {
        await _clearFor(generation);
        return false;
      }
      if (!_canRestore(refreshedCredentials)) {
        await _clearFor(generation);
        return false;
      }

      _pendingRotation = refreshedCredentials;
      await _writeCredentials(() async {
        if (generation == _generation) {
          await _credentialStore.save(refreshedCredentials);
        }
      });
      if (generation != _generation) return false;
      _pendingRotation = null;
      if (!await _applyStoredCredentials(refreshedCredentials, generation)) {
        return false;
      }
      LogService.instance.registerLog(
          "Refreshed Auth0 session from secure store.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return true;
    } catch (e) {
      if (generation != _generation) return false;
      // Only an explicit OAuth rejection proves a refresh token unusable.
      // Offline, authority and keychain failures retain recoverable credentials.
      if (e is FlutterAppAuthPlatformException &&
          e.platformErrorDetails.error ==
              FlutterAppAuthOAuthError.invalidGrant) {
        await _clearFor(generation);
      } else {
        // No automatic replay of a potentially consumed rotating token.
        _retryAfter = DateTime.now().add(retryDelay);
      }
      if (generation == _generation) _clearInMemorySession();
      LogService.instance.registerLog(
          "Auth0 refresh unavailable; sign-in or retry required.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return false;
    }
  }

  AuthCredentials _mergeRefreshedCredentials(
    AuthCredentials storedCredentials,
    AuthLoginResponse refreshResponse,
  ) {
    return AuthCredentials(
      accessToken: refreshResponse.accessToken,
      idToken: refreshResponse.idToken ?? storedCredentials.idToken,
      refreshToken:
          refreshResponse.refreshToken ?? storedCredentials.refreshToken,
      accessTokenExpiresAt: refreshResponse.accessTokenExpiresAt,
    );
  }

  Future<bool> _applyStoredCredentials(
      AuthCredentials credentials, int generation) async {
    if (generation != _generation) return false;
    _applyCredentials(credentials);
    if (_hasEmailClaim && identity != null) {
      return true;
    }

    await _rejectCredentialsWithoutEmail(
        function: "restoreStoredSession", generation: generation);
    return false;
  }

  void _applyCredentials(AuthCredentials credentials) {
    _accessToken = credentials.accessToken;
    _idToken = credentials.idToken;
    _email = _parseEmailFromIdToken(credentials.idToken);
    _profilePicture = _parseProfileFromIdToken(credentials.idToken);
  }

  void _clearInMemorySession() {
    _accessToken = null;
    _idToken = null;
    _email = null;
    _profilePicture = null;
  }

  bool get _hasEmailClaim => _email?.trim().isNotEmpty ?? false;

  Future<void> _rejectCredentialsWithoutEmail({
    required String function,
    required int generation,
  }) async {
    await _clearFor(generation);
    LogService.instance.registerLog(
        "Rejected Auth0 session without an email claim.",
        function: function,
        file: "auth0_service.dart");
  }

  bool get _isMobileAuthPlatform {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? _parseEmailFromIdToken(String? idToken) {
    if (idToken == null) return null;

    final payloadMap = _parseIdTokenPayload(idToken);
    final emailClaim = payloadMap?["email"];
    if (emailClaim is! String) return null;

    final normalizedEmail = emailClaim.trim();
    return normalizedEmail.isEmpty ? null : normalizedEmail;
  }

  String? _identityFromToken(String? token) {
    if (token == null) return null;
    final claims = _parseIdTokenPayload(token);
    final issuer = claims?["iss"];
    final subject = claims?["sub"];
    if (issuer is! String ||
        subject is! String ||
        subject.isEmpty ||
        issuer != "$_issuer/") {
      return null;
    }
    return "$issuer|$subject";
  }

  String? _parseProfileFromIdToken(String? idToken) {
    if (idToken == null) return null;

    final payloadMap = _parseIdTokenPayload(idToken);
    final pictureClaim = payloadMap?["picture"];
    if (pictureClaim is! String) return null;

    final normalizedPicture = pictureClaim.trim();
    return normalizedPicture.isEmpty ? null : normalizedPicture;
  }

  Map<String, dynamic>? _parseIdTokenPayload(String idToken) {
    // Split the token into its components
    final parts = idToken.split(".");
    if (parts.length != 3) return null;

    try {
      // Fix the padding issue for Base64
      String normalizedPayload = parts[1];
      normalizedPayload +=
          List.filled((4 - normalizedPayload.length % 4) % 4, "=").join();

      // Decode and parse the JSON payload
      final payload = utf8.decode(base64Url.decode(normalizedPayload));
      final decoded = json.decode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      LogService.instance.registerLog("Invalid Auth0 ID token payload.",
          function: "parseIdTokenPayload", file: "auth0_service.dart");
      return null;
    }
  }
}
