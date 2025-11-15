import "dart:convert";
import "package:flutter_appauth/flutter_appauth.dart";
import "log_service.dart";

// TODO: MOBILE ONLY

class AuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  // Replace with your Auth0 credentials
  final String _clientId = "wChCAH6ZES2UU8sGKRDjgN7JEETblQKf";
  final String _issuer = "https://keepeyeonball.eu.auth0.com";

  // Store access token and email
  String? _accessToken;
  String? _email;
  String? _profilePicture;

  String? get accessToken => _accessToken;
  String? get email => _email;

  String? get profilePicture => _profilePicture;

  Future<void> login() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          "com.hydracam://login-callback",
          issuer: _issuer,
          scopes: ["openid", "profile", "email"],
        ),
      );

      _accessToken = result.accessToken;
      final idToken = result.idToken; // Can parse for additional claims
      final email = _parseEmailFromIdToken(idToken);
      final profile = _parseProfileFromIdToken(idToken);
      _email = email;
      _profilePicture = profile;

      LogService.instance.registerLog("Profile set: $profile", function: "login", file: "auth0_service.dart");
    } catch (e) {
      throw Exception("Failed to log in: $e");
    }
  }

  String? _parseEmailFromIdToken(String? idToken) {
    if (idToken == null) return null;

    // Split the token into its components
    final parts = idToken.split(".");
    if (parts.length != 3) return null;

    // Fix the padding issue for Base64
    String normalizedPayload = parts[1];
    normalizedPayload += List.filled((4 - normalizedPayload.length % 4) % 4, "=").join();

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
    normalizedPayload += List.filled((4 - normalizedPayload.length % 4) % 4, "=").join();

    // Decode the payload
    final payload = utf8.decode(base64Url.decode(normalizedPayload));

    // Parse the JSON payload
    final payloadMap = json.decode(payload) as Map<String, dynamic>;

    // Extract profile picture URL
    _profilePicture = payloadMap["picture"] as String?;

    return _profilePicture;
  }
}
