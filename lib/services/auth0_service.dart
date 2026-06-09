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
    await _writeNullable(_accessTokenKey, credentials.accessToken);
    await _writeNullable(_idTokenKey, credentials.idToken);
    await _writeNullable(_refreshTokenKey, credentials.refreshToken);
    await _writeNullable(
      _expiresAtKey,
      credentials.accessTokenExpiresAt?.toIso8601String(),
    );
  }

  @override
  Future<AuthCredentials?> load() async {
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
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _idTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
  }

  Future<void> _writeNullable(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
      return;
    }

    await _storage.write(key: key, value: value);
  }
}

class AuthService {
  final AuthClient _authClient;
  final AuthCredentialStore _credentialStore;

  AuthService({
    AuthClient authClient = const FlutterAppAuthClient(),
    AuthCredentialStore credentialStore = const SecureAuthCredentialStore(),
  })  : _authClient = authClient,
        _credentialStore = credentialStore;

  static const List<String> authorizationScopes = [
    "openid",
    "profile",
    "email",
    "offline_access",
  ];

  // Replace with your Auth0 credentials
  final String _clientId = "wChCAH6ZES2UU8sGKRDjgN7JEETblQKf";
  final String _issuer = "https://keepeyeonball.eu.auth0.com";
  final String _redirectUrl = "com.hydracam://login-callback";
  final String _postLogoutRedirectUrl = "com.hydracam://login-callback";

  // Store access token and email
  String? _accessToken;
  String? _idToken;
  String? _email;
  String? _profilePicture;

  String? get accessToken => _accessToken;
  String? get email => _email;

  String? get profilePicture => _profilePicture;

  Future<void> login() async {
    if (!_isMobileAuthPlatform) {
      _clearInMemorySession();
      throw UnsupportedError(
        "Auth0 interactive login is only supported on Android and iOS.",
      );
    }

    try {
      final result = await _authClient.login(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
        issuer: _issuer,
        scopes: authorizationScopes,
      );

      _accessToken = result.accessToken;
      final idToken = result.idToken; // Can parse for additional claims
      _idToken = idToken;
      final email = _parseEmailFromIdToken(idToken);
      final profile = _parseProfileFromIdToken(idToken);
      _email = email;
      _profilePicture = profile;
      await _credentialStore.save(
        AuthCredentials(
          accessToken: result.accessToken,
          idToken: result.idToken,
          refreshToken: result.refreshToken,
          accessTokenExpiresAt: result.accessTokenExpiresAt,
        ),
      );

      LogService.instance.registerLog("Profile set: $profile",
          function: "login", file: "auth0_service.dart");
    } catch (e) {
      throw Exception("Failed to log in: $e");
    }
  }

  Future<void> logout() async {
    if (!_isMobileAuthPlatform) {
      _clearInMemorySession();
      LogService.instance.registerLog(
          "Skipped Auth0 logout on unsupported platform.",
          function: "logout",
          file: "auth0_service.dart");
      return;
    }

    final storedCredentials = await _credentialStore.load();
    final idToken = _idToken ?? storedCredentials?.idToken;

    try {
      if (idToken != null) {
        await _authClient.logout(
          idToken: idToken,
          postLogoutRedirectUrl: _postLogoutRedirectUrl,
          issuer: _issuer,
        );
      }
    } finally {
      await _credentialStore.clear();
      _clearInMemorySession();
      LogService.instance.registerLog("Cleared Auth0 session.",
          function: "logout", file: "auth0_service.dart");
    }
  }

  Future<bool> restoreStoredSession() async {
    if (!_isMobileAuthPlatform) {
      _clearInMemorySession();
      LogService.instance.registerLog(
          "Skipped Auth0 restore on unsupported platform.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return false;
    }

    final credentials = await _credentialStore.load();
    if (_canRestore(credentials)) {
      _applyCredentials(credentials!);
      LogService.instance.registerLog(
          "Restored Auth0 session from secure store.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return true;
    }

    if (_canRefresh(credentials)) {
      return _refreshStoredSession(credentials!);
    }

    _clearInMemorySession();
    return false;
  }

  bool _canRestore(AuthCredentials? credentials) {
    if (credentials?.accessToken == null || credentials?.idToken == null) {
      return false;
    }
    final expiresAt = credentials?.accessTokenExpiresAt;
    if (expiresAt == null) {
      return false;
    }
    return expiresAt.isAfter(DateTime.now());
  }

  bool _canRefresh(AuthCredentials? credentials) {
    return credentials?.refreshToken != null;
  }

  Future<bool> _refreshStoredSession(AuthCredentials credentials) async {
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
      if (!_canRestore(refreshedCredentials)) {
        _clearInMemorySession();
        return false;
      }

      await _credentialStore.save(refreshedCredentials);
      _applyCredentials(refreshedCredentials);
      LogService.instance.registerLog(
          "Refreshed Auth0 session from secure store.",
          function: "restoreStoredSession",
          file: "auth0_service.dart");
      return true;
    } catch (e) {
      _clearInMemorySession();
      LogService.instance.registerLog("Failed to refresh Auth0 session: $e",
          function: "restoreStoredSession", file: "auth0_service.dart");
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

  bool get _isMobileAuthPlatform {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  String? _parseEmailFromIdToken(String? idToken) {
    if (idToken == null) return null;

    // Split the token into its components
    final parts = idToken.split(".");
    if (parts.length != 3) return null;

    // Fix the padding issue for Base64
    String normalizedPayload = parts[1];
    normalizedPayload +=
        List.filled((4 - normalizedPayload.length % 4) % 4, "=").join();

    // Decode the payload
    final payload = utf8.decode(base64Url.decode(normalizedPayload));

    // Parse the JSON payload
    final payloadMap = json.decode(payload) as Map<String, dynamic>;

    // Extract email and profile picture URL
    _email = payloadMap["email"] as String?;

    return _email;
  }

  String? _parseProfileFromIdToken(String? idToken) {
    if (idToken == null) return null;

    // Split the token into its components
    final parts = idToken.split(".");
    if (parts.length != 3) return null;

    // Fix the padding issue for Base64
    String normalizedPayload = parts[1];
    normalizedPayload +=
        List.filled((4 - normalizedPayload.length % 4) % 4, "=").join();

    // Decode the payload
    final payload = utf8.decode(base64Url.decode(normalizedPayload));

    // Parse the JSON payload
    final payloadMap = json.decode(payload) as Map<String, dynamic>;

    // Extract profile picture URL
    _profilePicture = payloadMap["picture"] as String?;

    return _profilePicture;
  }
}
