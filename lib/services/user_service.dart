import 'dart:convert';

import 'auth0_service.dart';
import 'hydracam_api_service.dart';
import 'log_service.dart';
import 'package:http/http.dart' as http;


/// Singleton service to manage the current user's state and data.
class UserService {
  // Singleton instance
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final HydraCamApiService _apiService = HydraCamApiService();
  final AuthService _authService = AuthService();

  bool _isLoggedIn = false;
  String? _email;
  String? _guid;
  String? _profilePicture;

  bool get isLoggedIn => _isLoggedIn;
  String? get email => _email;
  String? get guid => _guid;
  String? get profilePicture => _profilePicture;

  final String baseUrl = "https://hydracam.azurewebsites.net/api/users/"; //TODO: MOVE TO API SERVICE

  /// Log in the user using Auth0 and fetch their GUID.
  Future<void> login() async {
    try {
      await _authService.login();
      _email = _authService.email;
      _profilePicture = _authService.profilePicture;

      print("Desde user service he puesto este profile: $_profilePicture");

      if (_email != null) {
        LogService.instance.registerLog('Fetching GUID for email: $_email');
        final fetchedGuid = await _apiService.getUserGuidByEmail(_email!);

        if (fetchedGuid != null) {
          _guid = fetchedGuid;
          _isLoggedIn = true;
          LogService.instance.registerLog('User logged in successfully. GUID: $_guid');
        } else {
          LogService.instance.registerLog('Failed to fetch GUID: User not found for $_email');
        }
      }
    } catch (e) {
      LogService.instance.registerLog('Error during login: $e');
      rethrow;
    }
  }

  /// Log out the user by clearing their state.
  Future<void> logout() async {
    _isLoggedIn = false;
    _email = null;
    _guid = null;
    LogService.instance.registerLog('User logged out.');
  }


  Future<Map<String, dynamic>?> fetchUserDetails(String guid) async {
    final response = await http.get(Uri.parse('$baseUrl$guid/info'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load user details');
    }
  }
}
