import 'dart:convert';
import 'package:http/http.dart' as http;
import 'log_service.dart';

class M2MAuthService {
  // Singleton instance
  static final M2MAuthService _instance = M2MAuthService._internal();
  factory M2MAuthService() => _instance;

  M2MAuthService._internal();

  // Token and expiration details
  String? _accessToken;
  DateTime? _expiresAt;

  // Auth0 details
  final String _clientId = 'wChCAH6ZES2UU8sGKRDjgN7JEETblQKf';
  final String _clientSecret = 'u1b25uMgtmX8Bl-N7Hr256zS1owso0Dfgh0EPccJwvFOW1Z3son19lt-Yh4eiIxm';
  final String _audience = 'https://hydracam/api';
  final String _tokenUrl = 'https://keepeyeonball.eu.auth0.com/oauth/token';

  /// Get M2M token, refreshing it if expired
  Future<String?> getToken() async {
    if (_accessToken != null && _expiresAt != null && DateTime.now().isBefore(_expiresAt!)) {
      return _accessToken;
    }

    return await _fetchToken();
  }

  /// Fetch a new token from Auth0
  Future<String?> _fetchToken() async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'audience': _audience,
          'grant_type': 'client_credentials',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _expiresAt = DateTime.now().add(Duration(seconds: data['expires_in']));

        LogService.instance.registerLog('M2M token obtained successfully');
        return _accessToken;
      } else {
        LogService.instance.registerLog('Failed to fetch M2M token: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error fetching M2M token: $e');
      return null;
    }
  }
}
