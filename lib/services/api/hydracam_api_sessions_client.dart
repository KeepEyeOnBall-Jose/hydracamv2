part of "../hydracam_api_service.dart";

/// Backend client for court/session lifecycle endpoints: catalog lookups
/// (courts, sports centers, sessions), session create/end, debug session
/// deletion, device readiness, and the startup warm-up probe.
class HydraCamSessionsClient {
  HydraCamSessionsClient(this._core);

  final HydraCamApiHttpCore _core;

  /// Fetch courts, optionally filtered by Sports Center GUID
  Future<List<Map<String, dynamic>>?> fetchCourts(
      {String? sportsCenterGuid}) async {
    try {
      final endpoint = hydracamApiEndpoint(
        HydraCamSessionContract.courtsEndpoint,
        queryParameters: {
          HydraCamSessionContract.querySportsCenterGuid: sportsCenterGuid,
        },
      );
      final response = await _core._get(endpoint);

      if (response is List) {
        // If the response is a list, parse it as a list of maps
        final parsedList = List<Map<String, dynamic>>.from(response);
        LogService.instance.registerLog("Parsed list (courts): $parsedList");
        return parsedList;
      } else {
        // If the response structure is unexpected, log it
        LogService.instance
            .registerLog("Unexpected structure (courts): $response");
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog("Error fetching courts: $e");
      return null;
    }
  }

  /// Fetch sports centers
  Future<List<Map<String, dynamic>>?> fetchSportsCenters() async {
    final response =
        await _core._get(HydraCamSessionContract.sportsCentersEndpoint);

    if (response is List) {
      // Parse the list of sports centers
      final parsedList = List<Map<String, dynamic>>.from(response);
      LogService.instance
          .registerLog("Parsed list (sportscenters): $parsedList");
      return parsedList;
    } else {
      LogService.instance
          .registerLog("Unexpected structure (sportscenters): $response");
      return null;
    }
  }

  /// Fetch sessions for a specific court
  Future<List<Map<String, dynamic>>?> fetchSessions(String courtGuid) async {
    try {
      // Construct the endpoint
      final endpoint = hydracamApiEndpoint(
        HydraCamSessionContract.sessionsEndpoint,
        queryParameters: {HydraCamSessionContract.queryCourtGuid: courtGuid},
      );

      // Fetch the response
      final response = await _core._get(endpoint);

      // Parse the response if it is a list
      if (response is List) {
        final parsedList = List<Map<String, dynamic>>.from(response);
        LogService.instance.registerLog("Parsed list (sessions): $parsedList");
        return parsedList;
      } else {
        // Log unexpected response structure
        LogService.instance
            .registerLog("Unexpected structure (sessions): $response");
        return null;
      }
    } catch (e) {
      // Handle and log exceptions
      LogService.instance.registerLog("Error fetching sessions: $e");
      return null;
    }
  }

  /// Notify server that device is ready to transmit
  Future<bool> notifyReadyToTransmit(
      String deviceId, String sessionGuid) async {
    try {
      final response = await _core._post(
        HydraCamSessionContract.readyToTransmitEndpoint,
        {
          "DeviceId": deviceId,
          "SessionGuid": sessionGuid,
        },
      );

      if (response != null) {
        LogService.instance
            .registerLog("Notified API that the device is ready to transmit");
        return true;
      } else {
        LogService.instance.registerLog("Failed to notify server: No response");
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog("Error notifying server: $e");
      return false;
    }
  }

  Future<bool> warmUpBackend({
    Duration timeout = HydraCamStartupWarmUpContract.timeout,
  }) async {
    try {
      final response = await _core
          ._get(HydraCamStartupWarmUpContract.endpoint)
          .timeout(timeout);
      final warmed = response != null;
      LogService.instance.registerLog(
        warmed
            ? "Backend warm-up completed."
            : "Backend warm-up did not return a usable response.",
      );
      return warmed;
    } on TimeoutException {
      LogService.instance.registerLog("Backend warm-up timed out.");
      return false;
    } catch (e) {
      LogService.instance.registerLog("Backend warm-up failed: $e");
      return false;
    }
  }

  /// Create a new capture session
  Future<HydraCamBackendSession?> createSession(String sessionId,
      {String? courtGuid, String? userGuid}) async {
    try {
      // Construct the endpoint with optional query parameters
      final endpoint = hydracamApiEndpoint(
        _core._createSessionEndpoint,
        queryParameters: {
          HydraCamSessionContract.queryCourtGuid: courtGuid,
          HydraCamSessionContract.queryUserGuid: userGuid,
        },
      );

      // Prepare the request body
      final body = {
        "SessionId": sessionId,
        "StartTime": DateTime.now().toIso8601String(),
      };

      final backendMode = _core._backendMode;
      final headers = await _core._getHeaders(
          authenticated: !_core._usesMediaTimelineBridge);

      // Make the POST request
      final uri = _core._apiUri(endpoint, backendMode: backendMode);
      final response = await _core._httpClient
          .post(uri, headers: headers, body: jsonEncode(body));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData is! Map) {
          LogService.instance.registerLog(
              "Failed to create session: unexpected response $responseData");
          return null;
        }
        final responseMap =
            responseData.map((key, value) => MapEntry(key.toString(), value));
        if (_core._responseMapReportsFailure(responseMap)) {
          LogService.instance.registerLog(
              "Failed to create session: backend response reported failure - ${_core._uploadFailureResponseBodySnippet(response.body)}");
          return null;
        }
        final backendSession = HydraCamBackendSession.fromCreateResponse(
          responseMap,
          requestedSessionId: sessionId,
        );
        LogService.instance
            .registerLog("Session created successfully: $backendSession");
        return backendSession;
      } else {
        LogService.instance
            .registerLog("Failed to create session: ${response.body}");
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog("Error creating session: $e");
      return null;
    }
  }

  /// End a session
  Future<bool> endSession(String sessionGuid) async {
    try {
      final backendMode = _core._backendMode;
      final response = await _core._post(
        hydracamApiEndpoint(
          _core._endSessionEndpoint,
          queryParameters: {
            HydraCamSessionContract.querySessionGuid: sessionGuid,
          },
        ),
        {},
        backendMode: backendMode,
        authenticated: backendMode == HydraCamApiBackendMode.legacyMobo,
      );
      if (response != null) {
        LogService.instance.registerLog("Session ended successfully");
        return true;
      }
      LogService.instance.registerLog("Failed to end session: No response");
      return false;
    } catch (e) {
      LogService.instance.registerLog("Error ending session: $e");
      return false;
    }
  }

  Future<bool> deleteDebugSession({
    required String sessionGuid,
    int? serviceNumericId,
  }) async {
    try {
      final response = await _core._post(
        hydracamApiEndpoint(
          HydraCamSessionContract.deleteDebugSessionEndpoint,
          queryParameters: {
            HydraCamSessionContract.querySessionGuid: sessionGuid,
            HydraCamSessionContract.querySessionNumericId:
                serviceNumericId?.toString(),
          },
        ),
        {},
      );
      if (response != null) {
        LogService.instance
            .registerLog("Debug session deleted from service: $sessionGuid");
        return true;
      }
      LogService.instance.registerLog(
          "Failed to delete debug session from service: $sessionGuid");
      return false;
    } catch (e) {
      LogService.instance
          .registerLog("Error deleting debug session from service: $e");
      return false;
    }
  }
}
