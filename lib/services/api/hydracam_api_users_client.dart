part of "../hydracam_api_service.dart";

/// Backend client for user directory lookups: resolving a user GUID from an
/// email address and fetching full user details by GUID.
class HydraCamUsersClient {
  HydraCamUsersClient(this._core);

  final HydraCamApiHttpCore _core;

  /// Get user GUID by email
  Future<String?> getUserGuidByEmail(String email) async {
    final endpoint = hydracamApiEndpoint(
      HydraCamUserContract.getByEmailEndpoint,
      queryParameters: {HydraCamUserContract.queryEmail: email},
    );
    final response = await _core._get(endpoint);
    return response?["guid"];
  }

  /// Fetch user details by GUID
  Future<Map?> fetchUserDetails(String guid) async {
    try {
      // Call the existing _get method with the appropriate endpoint
      final response = await _core._get(hydracamUserDetailsEndpoint(guid));

      if (response is Map) {
        // Return the user details if the response is a map
        return response;
      } else {
        // Log and return null if the response is not as expected
        LogService.instance
            .registerLog("Unexpected structure (user details): $response");
        return null;
      }
    } catch (e) {
      // Log any exceptions that occur
      LogService.instance.registerLog("Error fetching user details: $e");
      return null;
    }
  }
}
