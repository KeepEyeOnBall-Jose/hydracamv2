import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:package_info_plus/package_info_plus.dart";
import "log_service.dart";
import "auth0_m2m_service.dart";

class HydraCamUploadMediaContract {
  static const String method = "POST";
  static const int successStatusCode = 200;
  static const String endpoint = "sessions/upload-media";
  static const String querySessionGuid = "sessionGuid";
  static const String queryIsPhoto = "isPhoto";
  static const String fieldSlaveDeviceId = "slaveDeviceId";
  static const String fieldCaptureDate = "captureDate";
  static const String fieldReceivedDate = "receivedDate";
  static const String fieldRecordingEndDate = "recordingEndDate";
  static const String fieldDurationMs = "durationMs";
  static const String fieldAppVersion = "appVersion";
  static const String fieldAppBuildNumber = "appBuildNumber";
  static const String fileField = "files";
}

class HydraCamUserContract {
  static const String getByEmailEndpoint = "users/get-by-email";
  static const String queryEmail = "email";
}

class HydraCamSessionContract {
  static const String courtsEndpoint = "courts";
  static const String sportsCentersEndpoint = "sportscenters";
  static const String sessionsEndpoint = "sessions";
  static const String createSessionEndpoint = "sessions/create";
  static const String endSessionEndpoint = "sessions/end";
  static const String readyToTransmitEndpoint = "device/ReadyToTransmit";
  static const String querySportsCenterGuid = "sportsCenterGuid";
  static const String queryCourtGuid = "courtGuid";
  static const String queryUserGuid = "userGuid";
  static const String querySessionGuid = "sessionGuid";
}

@immutable
class HydraCamBackendSession {
  const HydraCamBackendSession({
    required this.guid,
    required this.sessionId,
    this.numericId,
  });

  final String guid;
  final String sessionId;
  final int? numericId;

  factory HydraCamBackendSession.fromCreateResponse(
    Map<String, dynamic> response, {
    required String requestedSessionId,
  }) {
    final rawGuid = response["guid"] ?? response["Guid"];
    final guid = rawGuid?.toString().trim() ?? "";
    if (guid.isEmpty) {
      throw const FormatException(
          "Session create response did not include a backend GUID.");
    }
    if (guid.startsWith("local-")) {
      throw FormatException(
          "Session create response returned a non-uploadable local GUID: $guid");
    }

    final rawId = response["id"] ?? response["Id"];
    final numericId =
        rawId is int ? rawId : int.tryParse(rawId?.toString() ?? "");
    final rawSessionId =
        response["sessionId"] ?? response["SessionId"] ?? requestedSessionId;
    return HydraCamBackendSession(
      guid: guid,
      sessionId: rawSessionId.toString(),
      numericId: numericId,
    );
  }

  @override
  String toString() {
    return "HydraCamBackendSession(guid: $guid, sessionId: $sessionId, numericId: $numericId)";
  }
}

String hydracamUserDetailsEndpoint(String guid) {
  return "users/${Uri.encodeComponent(guid)}/info";
}

String hydracamApiEndpoint(
  String path, {
  Map<String, String?> queryParameters = const {},
}) {
  final trimmedPath = path.startsWith("/") ? path.substring(1) : path;
  final effectiveQueryParameters = <String, String>{};
  for (final entry in queryParameters.entries) {
    final value = entry.value;
    if (value != null) {
      effectiveQueryParameters[entry.key] = value;
    }
  }

  return Uri(
    path: trimmedPath,
    queryParameters:
        effectiveQueryParameters.isEmpty ? null : effectiveQueryParameters,
  ).toString();
}

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

  void cancelInFlightRequests() {
    _httpClient.close();
    _httpClient = http.Client();
    LogService.instance.registerLog("Cancelled in-flight API requests.");
  }

  Uri _apiUri(String endpoint) {
    final baseUri = Uri.parse(_baseUrl);
    final endpointUri = Uri.parse(endpoint);
    final basePath = baseUri.path.endsWith("/")
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final endpointPath = endpointUri.path.startsWith("/")
        ? endpointUri.path.substring(1)
        : endpointUri.path;

    return baseUri.replace(
      path: endpointPath.isEmpty ? basePath : "$basePath/$endpointPath",
      queryParameters:
          endpointUri.hasQuery ? endpointUri.queryParameters : null,
    );
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
  Future<dynamic> _get(String endpoint) async {
    try {
      final headers = await _getHeaders();
      final uri = _apiUri(endpoint);
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
      final uri = _apiUri(endpoint);
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
      final endpoint = hydracamApiEndpoint(
        HydraCamSessionContract.courtsEndpoint,
        queryParameters: {
          HydraCamSessionContract.querySportsCenterGuid: sportsCenterGuid,
        },
      );
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
    final response = await _get(HydraCamSessionContract.sportsCentersEndpoint);

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

  /// Create a new capture session
  Future<HydraCamBackendSession?> createSession(String sessionId,
      {String? courtGuid, String? userGuid}) async {
    try {
      // Construct the endpoint with optional query parameters
      final endpoint = hydracamApiEndpoint(
        HydraCamSessionContract.createSessionEndpoint,
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

      final headers = await _getHeaders();

      // Make the POST request
      final uri = _apiUri(endpoint);
      final response =
          await _httpClient.post(uri, headers: headers, body: jsonEncode(body));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData is! Map) {
          LogService.instance.registerLog(
              "Failed to create session: unexpected response $responseData");
          return null;
        }
        final backendSession = HydraCamBackendSession.fromCreateResponse(
          responseData.map((key, value) => MapEntry(key.toString(), value)),
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
      final response = await _post(
        hydracamApiEndpoint(
          HydraCamSessionContract.endSessionEndpoint,
          queryParameters: {
            HydraCamSessionContract.querySessionGuid: sessionGuid,
          },
        ),
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
    Function(double)? onProgress, {
    DateTime? recordingEndDate,
    Duration? recordingDuration,
  }) async {
    try {
      if (!file.existsSync()) {
        LogService.instance
            .registerLog("Upload file does not exist: ${file.path}");
        return false;
      }

      final fileLength = await file.length();
      if (fileLength == 0) {
        LogService.instance.registerLog("Upload file is empty: ${file.path}");
        return false;
      }

      final headers = await _getHeaders();
      final appMetadata = await _getUploadAppMetadata();
      final uri = _apiUri(
        hydracamApiEndpoint(
          HydraCamUploadMediaContract.endpoint,
          queryParameters: {
            HydraCamUploadMediaContract.querySessionGuid: sessionGuid,
            HydraCamUploadMediaContract.queryIsPhoto: isPhoto.toString(),
          },
        ),
      );

      final request = http.MultipartRequest(
        HydraCamUploadMediaContract.method,
        uri,
      )
        ..headers.addAll(headers)
        ..fields[HydraCamUploadMediaContract.fieldSlaveDeviceId] = slaveDeviceId
        ..fields[HydraCamUploadMediaContract.fieldCaptureDate] =
            captureDate.toUtc().toIso8601String()
        ..fields[HydraCamUploadMediaContract.fieldReceivedDate] =
            receivedDate.toUtc().toIso8601String()
        ..fields.addAll(appMetadata);

      if (!isPhoto) {
        final effectiveDuration =
            recordingDuration ?? recordingEndDate?.difference(captureDate);
        if (recordingEndDate != null) {
          request.fields[HydraCamUploadMediaContract.fieldRecordingEndDate] =
              recordingEndDate.toUtc().toIso8601String();
        }
        if (effectiveDuration != null) {
          request.fields[HydraCamUploadMediaContract.fieldDurationMs] =
              effectiveDuration.inMilliseconds.toString();
        }
      }

      int uploadedBytes = 0;

      request.files.add(
        http.MultipartFile(
          HydraCamUploadMediaContract.fileField,
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

      if (response.statusCode ==
          HydraCamUploadMediaContract.successStatusCode) {
        if (_uploadResponseReportsFailure(response.body)) {
          LogService.instance.registerLog(
              "Failed to upload media: backend response reported failure - ${response.body}");
          return false;
        }
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

  bool _uploadResponseReportsFailure(String responseBody) {
    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty) {
      return false;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is! Map) {
        return false;
      }

      final successValue =
          decoded["success"] ?? decoded["succeeded"] ?? decoded["isSuccess"];
      if (successValue is bool) {
        return !successValue;
      }

      final statusValue = decoded["status"]?.toString().toLowerCase();
      return statusValue == "failed" ||
          statusValue == "failure" ||
          statusValue == "error";
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> _getUploadAppMetadata() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        HydraCamUploadMediaContract.fieldAppVersion: packageInfo.version,
        HydraCamUploadMediaContract.fieldAppBuildNumber:
            packageInfo.buildNumber,
      };
    } catch (e) {
      LogService.instance
          .registerLog("App version metadata unavailable for upload: $e");
      return {};
    }
  }

  /// Get user GUID by email
  Future<String?> getUserGuidByEmail(String email) async {
    final endpoint = hydracamApiEndpoint(
      HydraCamUserContract.getByEmailEndpoint,
      queryParameters: {HydraCamUserContract.queryEmail: email},
    );
    final response = await _get(endpoint);
    return response?["guid"];
  }

  /// Fetch user details by GUID
  Future<Map?> fetchUserDetails(String guid) async {
    try {
      // Call the existing _get method with the appropriate endpoint
      final response = await _get(hydracamUserDetailsEndpoint(guid));

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
