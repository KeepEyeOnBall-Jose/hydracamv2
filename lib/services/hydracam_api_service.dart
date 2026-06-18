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
  static const String deleteDebugSessionEndpoint = "sessions/debug/delete";
  static const String readyToTransmitEndpoint = "device/ReadyToTransmit";
  static const String querySportsCenterGuid = "sportsCenterGuid";
  static const String queryCourtGuid = "courtGuid";
  static const String queryUserGuid = "userGuid";
  static const String querySessionGuid = "sessionGuid";
  static const String querySessionNumericId = "id";
}

class HydraCamStartupWarmUpContract {
  static const String endpoint = HydraCamSessionContract.sportsCentersEndpoint;
  static const Duration timeout = Duration(seconds: 5);
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
    final guid = _parseBackendGuid(rawGuid);

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

  static String _parseBackendGuid(Object? rawGuid) {
    if (rawGuid == null) {
      throw const FormatException(
          "Session create response did not include a backend GUID.");
    }
    if (rawGuid is! String) {
      throw const FormatException(
          "Session create response returned a non-string backend GUID.");
    }

    final guid = rawGuid.trim();
    if (guid.isEmpty) {
      throw const FormatException(
          "Session create response did not include a backend GUID.");
    }

    final normalizedGuid = guid.toLowerCase();
    if (normalizedGuid.startsWith("local-") ||
        normalizedGuid == "null" ||
        normalizedGuid == "undefined") {
      throw FormatException(
          "Session create response returned an invalid backend GUID: $guid");
    }
    return guid;
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

  static const String _legacyUploadSuccessBody = "Media uploaded successfully.";
  static const int _uploadFailureResponseBodyLogLimit = 300;
  static const Set<String> _photoIsoBaseMediaBrands = {
    "heic",
    "heix",
    "hevc",
    "hevx",
    "mif1",
    "msf1",
  };
  static const Set<String> _videoIsoBaseMediaBrands = {
    "3gp4",
    "avc1",
    "isom",
    "iso2",
    "M4A ",
    "M4V ",
    "mp41",
    "mp42",
    "qt  ",
  };

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
        return _decodeSuccessfulPostResponse(endpoint, response.body);
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

  Map<String, dynamic>? _decodeSuccessfulPostResponse(
    String endpoint,
    String responseBody,
  ) {
    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is Map) {
        final decodedMap =
            decoded.map((key, value) => MapEntry(key.toString(), value));
        if (_responseMapReportsFailure(decodedMap)) {
          LogService.instance.registerLog(
              "POST $endpoint reported failure: ${_uploadFailureResponseBodySnippet(responseBody)}");
          return null;
        }
        return decodedMap;
      }

      LogService.instance.registerLog(
          "POST $endpoint returned unexpected JSON success body: $decoded");
      return <String, dynamic>{};
    } on FormatException {
      LogService.instance.registerLog(
          "POST $endpoint returned non-JSON success body: ${_uploadFailureResponseBodySnippet(responseBody)}");
      return <String, dynamic>{};
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

  Future<bool> warmUpBackend({
    Duration timeout = HydraCamStartupWarmUpContract.timeout,
  }) async {
    try {
      final response =
          await _get(HydraCamStartupWarmUpContract.endpoint).timeout(timeout);
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
        final responseMap =
            responseData.map((key, value) => MapEntry(key.toString(), value));
        if (_responseMapReportsFailure(responseMap)) {
          LogService.instance.registerLog(
              "Failed to create session: backend response reported failure - ${_uploadFailureResponseBodySnippet(response.body)}");
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

  Future<bool> deleteDebugSession({
    required String sessionGuid,
    int? serviceNumericId,
  }) async {
    try {
      final response = await _post(
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
    Function(String)? onFailureReason,
  }) async {
    try {
      if (!file.existsSync()) {
        return _failUpload(
          "Upload file does not exist: ${file.path}",
          onFailureReason: onFailureReason,
          mediaFailureReason:
              "Upload failed: file does not exist: ${file.path}",
        );
      }

      final fileLength = await file.length();
      if (fileLength == 0) {
        return _failUpload(
          "Upload file is empty: ${file.path}",
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: file is empty: ${file.path}",
        );
      }

      final validationFailure = await _uploadMediaValidationFailure(
        file: file,
        isPhoto: isPhoto,
      );
      if (validationFailure != null) {
        return _failUpload(
          validationFailure,
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $validationFailure",
        );
      }

      final Duration? effectiveVideoDuration;
      if (isPhoto) {
        effectiveVideoDuration = null;
      } else {
        effectiveVideoDuration =
            recordingEndDate?.difference(captureDate) ?? recordingDuration;
        if (effectiveVideoDuration != null &&
            effectiveVideoDuration.isNegative) {
          final failureReason =
              "Upload video duration is invalid: recordingEndDate is before captureDate for ${file.path}";
          return _failUpload(
            failureReason,
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $failureReason",
          );
        }
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
        if (recordingEndDate != null) {
          request.fields[HydraCamUploadMediaContract.fieldRecordingEndDate] =
              recordingEndDate.toUtc().toIso8601String();
        }
        if (effectiveVideoDuration != null) {
          request.fields[HydraCamUploadMediaContract.fieldDurationMs] =
              effectiveVideoDuration.inMilliseconds.toString();
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
          final failureReason =
              "HTTP ${response.statusCode} backend response reported failure - ${_uploadFailureResponseBodySnippet(response.body)}";
          return _failUpload(
            "Failed to upload media: $failureReason",
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $failureReason",
          );
        }
        LogService.instance.registerLog("Media uploaded successfully");
        return true;
      } else {
        final failureReason =
            "HTTP ${response.statusCode} - ${_uploadFailureResponseBodySnippet(response.body)}";
        return _failUpload(
          "Failed to upload media: $failureReason",
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $failureReason",
        );
      }
    } catch (e) {
      return _failUpload(
        "Error uploading media: $e",
        onFailureReason: onFailureReason,
        mediaFailureReason: "Upload failed: $e",
      );
    }
  }

  bool _failUpload(
    String logMessage, {
    Function(String)? onFailureReason,
    String? mediaFailureReason,
  }) {
    LogService.instance.registerLog(logMessage);
    onFailureReason?.call(mediaFailureReason ?? logMessage);
    return false;
  }

  Future<String?> _uploadMediaValidationFailure({
    required File file,
    required bool isPhoto,
  }) async {
    final header = await _readFileHeader(file, 16);
    final isValidMedia = isPhoto
        ? _hasPhotoMediaSignature(header)
        : _hasVideoMediaSignature(header);
    if (isValidMedia) {
      return null;
    }

    final mediaType = isPhoto ? "photo" : "video";
    return "Upload file is not valid $mediaType media: ${file.path}";
  }

  Future<List<int>> _readFileHeader(File file, int byteCount) async {
    final randomAccessFile = await file.open();
    try {
      return await randomAccessFile.read(byteCount);
    } finally {
      await randomAccessFile.close();
    }
  }

  bool _hasPhotoMediaSignature(List<int> header) {
    return _hasJpegSignature(header) ||
        _hasPngSignature(header) ||
        _hasIsoBaseMediaSignature(header, _photoIsoBaseMediaBrands);
  }

  bool _hasVideoMediaSignature(List<int> header) {
    return _hasIsoBaseMediaSignature(header, _videoIsoBaseMediaBrands);
  }

  bool _hasJpegSignature(List<int> header) {
    return header.length >= 2 && header[0] == 0xff && header[1] == 0xd8;
  }

  bool _hasPngSignature(List<int> header) {
    const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (header.length < pngSignature.length) {
      return false;
    }
    for (var index = 0; index < pngSignature.length; index += 1) {
      if (header[index] != pngSignature[index]) {
        return false;
      }
    }
    return true;
  }

  bool _hasIsoBaseMediaSignature(
    List<int> header,
    Set<String> supportedMajorBrands,
  ) {
    if (header.length < 12 ||
        header[4] != 0x66 ||
        header[5] != 0x74 ||
        header[6] != 0x79 ||
        header[7] != 0x70) {
      return false;
    }

    final majorBrand = String.fromCharCodes(header.sublist(8, 12));
    return supportedMajorBrands.contains(majorBrand);
  }

  bool _uploadResponseReportsFailure(String responseBody) {
    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty) {
      return false;
    }
    if (trimmedBody == _legacyUploadSuccessBody) {
      return false;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is! Map) {
        return true;
      }

      final decodedMap =
          decoded.map((key, value) => MapEntry(key.toString(), value));
      return _responseMapReportsFailure(decodedMap);
    } catch (e) {
      LogService.instance
          .registerLog("Malformed upload response body: $trimmedBody ($e)");
      return true;
    }
  }

  bool _responseMapReportsFailure(Map<String, dynamic> decoded) {
    final successValue =
        decoded["success"] ?? decoded["succeeded"] ?? decoded["isSuccess"];
    final parsedSuccessValue = _parseResponseSuccessValue(successValue);
    if (parsedSuccessValue != null) {
      return !parsedSuccessValue;
    }

    final errorValue = decoded["error"] ?? decoded["errors"];
    if (_hasMeaningfulErrorValue(errorValue)) {
      return true;
    }

    final statusValue = decoded["status"]?.toString().toLowerCase();
    return statusValue == "failed" ||
        statusValue == "failure" ||
        statusValue == "error";
  }

  bool? _parseResponseSuccessValue(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case "true":
        case "1":
        case "yes":
        case "y":
        case "success":
        case "succeeded":
          return true;
        case "false":
        case "0":
        case "no":
        case "n":
        case "failed":
        case "failure":
        case "error":
          return false;
      }
    }
    return null;
  }

  bool _hasMeaningfulErrorValue(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is Iterable) {
      return value.isNotEmpty;
    }
    if (value is Map) {
      return value.isNotEmpty;
    }
    return true;
  }

  String _uploadFailureResponseBodySnippet(String responseBody) {
    final normalizedBody = responseBody.trim().replaceAll(
          RegExp(r"\s+"),
          " ",
        );
    if (normalizedBody.isEmpty) {
      return "<empty>";
    }
    if (normalizedBody.length <= _uploadFailureResponseBodyLogLimit) {
      return normalizedBody;
    }
    return "${normalizedBody.substring(0, _uploadFailureResponseBodyLogLimit)}...";
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
