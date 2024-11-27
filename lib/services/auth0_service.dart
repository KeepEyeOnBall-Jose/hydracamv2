import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';

// TODO: MOBILE ONLY

class AuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  // Replace with your Auth0 credentials
  final String _clientId = 'wChCAH6ZES2UU8sGKRDjgN7JEETblQKf';
  final String _issuer = 'https://keepeyeonball.eu.auth0.com';

  // Store access token and email
  String? _accessToken;
  String? _email;

  String? get accessToken => _accessToken;
  String? get email => _email;

  Future<void> login() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          'com.hydracam://login-callback',
          issuer: _issuer,
          scopes: ['openid', 'profile', 'email'],
        ),
      );

      if (result != null) {
        _accessToken = result.accessToken;
        final idToken = result.idToken; // Can parse for additional claims
        final email = _parseEmailFromIdToken(idToken);
        _email = email;
      }
    } catch (e) {
      throw Exception('Failed to log in: $e');
    }
  }

  String? _parseEmailFromIdToken(String? idToken) {
    if (idToken == null) return null;

    // Decode and parse JWT (for simplicity using string split)
    final parts = idToken.split('.');
    if (parts.length != 3) return null;

    final payload = Uri.decodeComponent(
      String.fromCharCodes(base64Url.decode(parts[1])),
    );

    final payloadMap = json.decode(payload) as Map<String, dynamic>;
    return payloadMap['email'] as String?;
  }
}
