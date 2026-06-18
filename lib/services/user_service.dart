import "package:flutter/foundation.dart";

import "auth0_service.dart";
import "hydracam_api_service.dart";
import "log_service.dart";

typedef UserGuidLookup = Future<String?> Function(String email);
typedef UserDetailsLookup = Future<Map?> Function(String guid);

/// Singleton service to manage the current user's state and data.
class UserService {
  // Singleton instance
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal()
      : _authService = AuthService(),
        _getUserGuidByEmail = HydraCamApiService().getUserGuidByEmail,
        _fetchUserDetailsByGuid = HydraCamApiService().fetchUserDetails;

  @visibleForTesting
  UserService.forTesting({
    required AuthService authService,
    required UserGuidLookup getUserGuidByEmail,
    UserDetailsLookup? fetchUserDetailsByGuid,
  })  : _authService = authService,
        _getUserGuidByEmail = getUserGuidByEmail,
        _fetchUserDetailsByGuid = fetchUserDetailsByGuid ?? ((_) async => null);

  final AuthService _authService;
  final UserGuidLookup _getUserGuidByEmail;
  final UserDetailsLookup _fetchUserDetailsByGuid;

  bool _isLoggedIn = false;
  String? _email;
  String? _guid;
  String? _profilePicture;

  bool get isLoggedIn => _isLoggedIn;
  String? get email => _email;
  String? get guid => _guid;
  String? get profilePicture => _profilePicture;

  /// Log in the user using Auth0 and fetch their GUID.
  Future<void> login() async {
    _clearUserState();
    try {
      await _authService.login();
      _email = _authService.email;
      _profilePicture = _authService.profilePicture;

      LogService.instance.registerLog(
          "Profile set from user service: $_profilePicture",
          function: "login",
          file: "user_service.dart");

      final loginEmail = _email?.trim();
      if (loginEmail != null && loginEmail.isNotEmpty) {
        _email = loginEmail;
        LogService.instance.registerLog("Fetching GUID for email: $loginEmail");
        final fetchedGuid = await _getUserGuidByEmail(loginEmail);

        if (fetchedGuid != null) {
          _guid = fetchedGuid;
          _isLoggedIn = true;
          LogService.instance
              .registerLog("User logged in successfully. GUID: $_guid");
        } else {
          _clearUserState();
          LogService.instance.registerLog(
              "Failed to fetch GUID: User not found for $loginEmail");
        }
      } else {
        _clearUserState();
      }
    } catch (e) {
      _clearUserState();
      LogService.instance.registerLog("Error during login: $e");
      rethrow;
    }
  }

  Future<bool> restoreStoredSession() async {
    try {
      final restored = await _authService.restoreStoredSession();
      if (!restored) {
        _clearUserState();
        return false;
      }

      _email = _authService.email;
      _profilePicture = _authService.profilePicture;
      final restoredEmail = _email?.trim();
      if (restoredEmail == null || restoredEmail.isEmpty) {
        _clearUserState();
        return false;
      }

      _email = restoredEmail;
      LogService.instance
          .registerLog("Fetching restored GUID for email: $restoredEmail");
      final fetchedGuid = await _getUserGuidByEmail(restoredEmail);
      if (fetchedGuid == null) {
        _clearUserState();
        LogService.instance
            .registerLog("Failed to fetch restored GUID for $restoredEmail");
        return false;
      }

      _guid = fetchedGuid;
      _isLoggedIn = true;
      LogService.instance.registerLog("User session restored. GUID: $_guid");
      return true;
    } catch (e) {
      _clearUserState();
      LogService.instance.registerLog("Error during restore: $e");
      return false;
    }
  }

  /// Log out the user by clearing their state.
  Future<void> logout() async {
    try {
      await _authService.logout();
    } finally {
      _clearUserState();
      LogService.instance.registerLog("User logged out.");
    }
  }

  Future<Map<String, dynamic>?> fetchUserDetails(String guid) async {
    try {
      // Call the new fetchUserDetails method from HydraCamApiService
      final response = await _fetchUserDetailsByGuid(guid);

      if (response != null) {
        // Ensure the response is a Map<String, dynamic>
        return Map<String, dynamic>.from(response);
      } else {
        // Log an error if the response is null
        LogService.instance.registerLog("Error: User details not found.",
            function: "fetchUserDetails", file: "user_service.dart");
        throw Exception("Failed to load user details");
      }
    } catch (e) {
      // Log any exceptions
      LogService.instance.registerLog("Exception: $e",
          function: "fetchUserDetails", file: "user_service.dart");
      rethrow;
    }
  }

  void _clearUserState() {
    _isLoggedIn = false;
    _email = null;
    _guid = null;
    _profilePicture = null;
  }
}
