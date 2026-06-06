import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "log_service.dart";
import "auth0_m2m_service.dart";

/// Singleton class to manage API communication for HydraCam
class HydraCamApiService {
  // Singleton instance
  static final HydraCamApiService _instance = HydraCamApiService._internal();
  factory HydraCamApiService() => _instance;

  HydraCamApiService._internal();

  // Base URL for the API
  final String _baseUrl = "https://hydracam.azurewebsites.net/api";

  http.Client _httpClient = http.Client();

  @visibleForTesting
  static void configureHttpClient(http.Client client) {
    _instance._httpClient = client;
  }

  @visibleForTesting
  static void resetHttpClient() {
    _instance._httpClient = http.Client();
  }

  /// Obtiene las cabeceras comunes, incluyendo `Authorization: Bearer <token>`.
  Future<Map<String, String>> _getHeaders() async {
    final token = await M2MAuthService().getToken();
    if (token == null) {
      throw Exception("Failed to retrieve M2M token");
    }
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  /// Generic GET request with headers and parsing
  /// Generic GET request with headers and parsing
  Future<dynamic> _get(String endpoint) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse("$_baseUrl/$endpoint".replaceAll(" ", ""));
      final response = await _httpClient.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          // Return list directly if response is a JSON array
          return decoded;
        } else if (decoded is Map) {
          // Return map if response is a JSON object
          return decoded;
        } else {
          // Log unexpected structure
          LogService.instance
              .registerLog("Unexpected JSON structure: $decoded");
          return null;
        }
      } else {
        // Log non-200 responses
        LogService.instance.registerLog(
            "GET $endpoint failed: StatusCode=${response.statusCode}, Body=${response.body}");
        return null;
      }
    } catch (e) {
      // Log errors
      LogService.instance.registerLog("Error on GET $endpoint: $e");
      return null;
    }
  }

  /// Realiza un POST genérico con headers y parsing
  Future<Map<String, dynamic>?> _post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse("$_baseUrl / $endpoint".replaceAll(" ", ""));
      final response =
          await _httpClient.post(uri, headers: headers, body: jsonEncode(body));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        LogService.instance
            .registerLog("POST $endpoint failed: ${response.body}");
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog("Error on POST $endpoint: $e");
      return null;
    }
  }

  /// Fetch courts, optionally filtered by Sports Center GUID
  Future<List<Map<String, dynamic>>?> fetchCourts(
      {String? sportsCenterGuid}) async {
    try {
      final endpoint = sportsCenterGuid != null
          ? "courts?sportsCenterGuid=$sportsCenterGuid"
          : "courts";
      final response = await _get(endpoint);

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
    final response = await _get("sportscenters");

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
      final endpoint = "sessions?courtGuid=$courtGuid";

      // Fetch the response
      final response = await _get(endpoint);

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
      final response = await _post(
        "device/ReadyToTransmit",
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

  /// Create a new capture session
  /// Create a new capture session
  Future<Map<String, dynamic>?> createSession(String sessionId,
      {String? courtGuid, String? userGuid}) async {
    try {
      // Construct the endpoint with optional query parameters
      String endpoint = "sessions/create";
      if (courtGuid != null || userGuid != null) {
        final queryParameters = <String, String>{};
        if (courtGuid != null) queryParameters["courtGuid"] = courtGuid;
        if (userGuid != null) queryParameters["userGuid"] = userGuid;

        endpoint += "?${Uri(queryParameters: queryParameters).query}";
      }

      // Prepare the request body
      final body = {
        "SessionId": sessionId,
        "StartTime": DateTime.now().toIso8601String(),
      };

      final headers = await _getHeaders();

      // Make the POST request
      final uri = Uri.parse("$_baseUrl/$endpoint");
      final response =
          await _httpClient.post(uri, headers: headers, body: jsonEncode(body));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        LogService.instance
            .registerLog("Session created successfully: $responseData");
        return responseData;
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
      final response = await _post(
        "sessions/end?sessionGuid=$sessionGuid",
        {},
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

  /// Upload media
  Future<bool> uploadMedia(
    String sessionGuid,
    File file,
    bool isPhoto,
    String slaveDeviceId,
    DateTime captureDate,
    DateTime receivedDate,
    Function(double)? onProgress,
  ) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse(
          "$_baseUrl/sessions/upload-media?sessionGuid=$sessionGuid&isPhoto=$isPhoto");

      final request = http.MultipartRequest("POST", uri)
        ..headers.addAll(headers)
        ..fields["slaveDeviceId"] = slaveDeviceId
        ..fields["captureDate"] = captureDate.toUtc().toIso8601String()
        ..fields["receivedDate"] = receivedDate.toUtc().toIso8601String();

      final fileLength = await file.length();
      int uploadedBytes = 0;

      request.files.add(
        http.MultipartFile(
          "files",
          file.openRead().transform(
            StreamTransformer.fromHandlers(
              handleData: (chunk, sink) {
                uploadedBytes += chunk.length;
                onProgress?.call(uploadedBytes / fileLength);
                sink.add(chunk);
              },
            ),
          ),
          fileLength,
          filename: file.path.split("/").last,
        ),
      );

      final streamedResponse = await _httpClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        LogService.instance.registerLog("Media uploaded successfully");
        return true;
      } else {
        LogService.instance.registerLog(
            "Failed to upload media: ${response.statusCode} - ${response.body}");
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog("Error uploading media: $e");
      return false;
    }
  }

  /// Get user GUID by email
  Future<String?> getUserGuidByEmail(String email) async {
    final response = await _get("users/get-by-email?email=$email");
    return response?["guid"];
  }

  /// Fetch user details by GUID
  Future<Map?> fetchUserDetails(String guid) async {
    try {
      // Call the existing _get method with the appropriate endpoint
      final response = await _get("users/$guid/info");

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
