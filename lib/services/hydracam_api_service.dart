import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:http_parser/http_parser.dart";
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

class HydraCamBridgeSessionContract {
  static const String createSessionEndpoint =
      "hydracam-bridge/compat/sessions/create";
  static const String endSessionEndpoint =
      "hydracam-bridge/compat/sessions/end";
  static const String uploadMediaEndpoint =
      "hydracam-bridge/compat/sessions/upload-media";
}

String hydracamBridgeDirectUploadStartEndpoint(String sessionGuid) {
  return "hydracam-bridge/sessions/$sessionGuid/uploads/start";
}

enum HydraCamApiBackendMode {
  legacyMobo,
  mediaTimelineBridge,
}

@immutable
class HydraCamUploadFileResult {
  const HydraCamUploadFileResult({
    required this.fileId,
    required this.filename,
    required this.kind,
    this.eventId,
    this.sessionGuid,
    this.sourceId,
    this.storage,
  });

  final String fileId;
  final String filename;
  final String kind;
  final String? eventId;
  final String? sessionGuid;
  final String? sourceId;
  final String? storage;

  factory HydraCamUploadFileResult.fromJson(Map<String, dynamic> json) {
    return HydraCamUploadFileResult(
      fileId: _requiredString(json["fileId"], "fileId"),
      filename: _requiredString(json["filename"], "filename"),
      kind: _requiredString(json["kind"], "kind"),
      eventId: _optionalString(json["eventId"]),
      sessionGuid: _optionalString(json["sessionGuid"]),
      sourceId: _optionalString(json["sourceId"]),
      storage: _optionalString(json["storage"]),
    );
  }
}

@immutable
class HydraCamUploadResult {
  const HydraCamUploadResult({
    required this.eventId,
    required this.sessionGuid,
    required this.files,
  });

  final String eventId;
  final String sessionGuid;
  final List<HydraCamUploadFileResult> files;

  factory HydraCamUploadResult.fromJson(Map<String, dynamic> json) {
    final rawFiles = json["files"];
    if (rawFiles is! List) {
      throw const FormatException(
          "Upload response is missing File Registry files.");
    }
    final files = rawFiles
        .map((rawFile) => HydraCamUploadFileResult.fromJson(
              _asStringKeyedMap(rawFile),
            ))
        .toList(growable: false);
    if (files.isEmpty) {
      throw const FormatException(
          "Upload response did not include File Registry files.");
    }
    return HydraCamUploadResult(
      eventId: _requiredString(json["eventId"], "eventId"),
      sessionGuid: _requiredString(json["sessionGuid"], "sessionGuid"),
      files: files,
    );
  }
}

@immutable
class HydraCamBridgeMediaStoragePaths {
  const HydraCamBridgeMediaStoragePaths({
    required this.startPath,
    required this.signPartPath,
    required this.uploadPartPath,
    required this.completeObjectPath,
    required this.completeBridgePath,
  });

  final String startPath;
  final String signPartPath;
  final String uploadPartPath;
  final String completeObjectPath;
  final String completeBridgePath;

  factory HydraCamBridgeMediaStoragePaths.fromJson(Map<String, dynamic> json) {
    return HydraCamBridgeMediaStoragePaths(
      startPath: _requiredString(json["startPath"], "mediaStorage.startPath"),
      signPartPath:
          _requiredString(json["signPartPath"], "mediaStorage.signPartPath"),
      uploadPartPath: _requiredString(
          json["uploadPartPath"], "mediaStorage.uploadPartPath"),
      completeObjectPath: _requiredString(
          json["completeObjectPath"], "mediaStorage.completeObjectPath"),
      completeBridgePath: _requiredString(
          json["completeBridgePath"], "mediaStorage.completeBridgePath"),
    );
  }
}

@immutable
class HydraCamDirectUploadStart {
  const HydraCamDirectUploadStart({
    required this.eventId,
    required this.sessionGuid,
    required this.objectKey,
    required this.preferredStorage,
    required this.mediaStorage,
  });

  final String eventId;
  final String sessionGuid;
  final String objectKey;
  final String preferredStorage;
  final HydraCamBridgeMediaStoragePaths mediaStorage;

  factory HydraCamDirectUploadStart.fromJson(Map<String, dynamic> json) {
    return HydraCamDirectUploadStart(
      eventId: _requiredString(json["eventId"], "eventId"),
      sessionGuid: _requiredString(json["sessionGuid"], "sessionGuid"),
      objectKey: _requiredString(json["objectKey"], "objectKey"),
      preferredStorage:
          _requiredString(json["preferredStorage"], "preferredStorage"),
      mediaStorage: HydraCamBridgeMediaStoragePaths.fromJson(
        _asStringKeyedMap(json["mediaStorage"]),
      ),
    );
  }
}

class _MediaStorageMultipartStart {
  const _MediaStorageMultipartStart({
    required this.key,
    required this.uploadId,
    required this.locator,
  });

  final String key;
  final String uploadId;
  final String locator;

  factory _MediaStorageMultipartStart.fromJson(Map<String, dynamic> json) {
    return _MediaStorageMultipartStart(
      key: _requiredString(json["key"], "key"),
      uploadId: _requiredString(json["uploadId"], "uploadId"),
      locator: _requiredString(json["locator"], "locator"),
    );
  }
}

class _MediaStorageUploadedPart {
  const _MediaStorageUploadedPart({
    required this.partNumber,
    required this.eTag,
  });

  final int partNumber;
  final String eTag;

  Map<String, dynamic> toJson() {
    return {
      "PartNumber": partNumber,
      "ETag": eTag,
    };
  }

  factory _MediaStorageUploadedPart.fromJson(Map<String, dynamic> json) {
    final rawPartNumber = json["PartNumber"] ?? json["partNumber"];
    final partNumber = rawPartNumber is int
        ? rawPartNumber
        : int.tryParse(rawPartNumber?.toString() ?? "");
    if (partNumber == null || partNumber < 1) {
      throw const FormatException(
          "Upload part response is missing PartNumber.");
    }
    return _MediaStorageUploadedPart(
      partNumber: partNumber,
      eTag: _requiredString(json["ETag"] ?? json["etag"], "ETag"),
    );
  }
}

class _MediaStorageComplete {
  const _MediaStorageComplete({
    required this.locator,
    required this.fileId,
  });

  final String locator;
  final String fileId;

  factory _MediaStorageComplete.fromJson(Map<String, dynamic> json) {
    final registered = _asStringKeyedMap(json["registered"]);
    return _MediaStorageComplete(
      locator: _requiredString(json["locator"], "locator"),
      fileId: _requiredString(registered["fileId"], "registered.fileId"),
    );
  }
}

class _HydraCamBridgeCompletedUpload {
  const _HydraCamBridgeCompletedUpload({
    required this.eventId,
    required this.fileId,
  });

  final String eventId;
  final String fileId;

  factory _HydraCamBridgeCompletedUpload.fromJson(Map<String, dynamic> json) {
    return _HydraCamBridgeCompletedUpload(
      eventId: _requiredString(json["eventId"], "eventId"),
      fileId: _requiredString(json["fileId"], "fileId"),
    );
  }
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
    this.mediaTimelineEventId,
    this.uploadToken,
    this.uploadTokenExpiresAt,
  });

  final String guid;
  final String sessionId;
  final int? numericId;
  final String? mediaTimelineEventId;
  final String? uploadToken;
  final int? uploadTokenExpiresAt;

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
    final rawUploadTokenExpiresAt =
        response["uploadTokenExpiresAt"] ?? response["UploadTokenExpiresAt"];
    return HydraCamBackendSession(
      guid: guid,
      sessionId: rawSessionId.toString(),
      numericId: numericId,
      mediaTimelineEventId:
          _optionalString(response["eventId"] ?? response["EventId"]),
      uploadToken:
          _optionalString(response["uploadToken"] ?? response["UploadToken"]),
      uploadTokenExpiresAt: rawUploadTokenExpiresAt is int
          ? rawUploadTokenExpiresAt
          : int.tryParse(rawUploadTokenExpiresAt?.toString() ?? ""),
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

Map<String, dynamic> _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException("Expected a JSON object.");
}

String _requiredString(Object? value, String fieldName) {
  final text = _optionalString(value);
  if (text == null) {
    throw FormatException("Upload response is missing $fieldName.");
  }
  return text;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
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

  static const String _defaultLegacyBaseUrl = String.fromEnvironment(
    "HYDRACAM_API_BASE_URL",
    defaultValue: "https://hydracam.azurewebsites.net/api",
  );
  static const String _defaultMediaTimelineBaseUrl = String.fromEnvironment(
    "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL",
    defaultValue: "http://127.0.0.1:3001/api",
  );
  static const bool _defaultUseMediaTimelineBridge = bool.fromEnvironment(
    "HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE",
    defaultValue: false,
  );

  String _legacyBaseUrl = _defaultLegacyBaseUrl;
  String _mediaTimelineBaseUrl = _defaultMediaTimelineBaseUrl;
  HydraCamApiBackendMode _backendMode = _defaultUseMediaTimelineBridge
      ? HydraCamApiBackendMode.mediaTimelineBridge
      : HydraCamApiBackendMode.legacyMobo;
  int _mediaTimelineBridgeRetryMaxAttempts = 7;
  Duration _mediaTimelineBridgeRetryInitialDelay = const Duration(seconds: 1);

  http.Client _httpClient = http.Client();

  @visibleForTesting
  static void configureHttpClient(http.Client client) {
    _instance._httpClient = client;
  }

  @visibleForTesting
  static void resetHttpClient() {
    _instance._httpClient = http.Client();
  }

  @visibleForTesting
  static void configureBridgeRetryForTests({
    int? maxAttempts,
    Duration? initialDelay,
  }) {
    if (maxAttempts != null) {
      _instance._mediaTimelineBridgeRetryMaxAttempts = maxAttempts;
    }
    if (initialDelay != null) {
      _instance._mediaTimelineBridgeRetryInitialDelay = initialDelay;
    }
  }

  @visibleForTesting
  static void configureBackendForTests({
    required HydraCamApiBackendMode mode,
    String? baseApiUrl,
  }) {
    _instance._backendMode = mode;
    if (baseApiUrl == null) {
      return;
    }
    switch (mode) {
      case HydraCamApiBackendMode.legacyMobo:
        _instance._legacyBaseUrl = baseApiUrl;
      case HydraCamApiBackendMode.mediaTimelineBridge:
        _instance._mediaTimelineBaseUrl = baseApiUrl;
    }
  }

  @visibleForTesting
  static void resetBackendForTests() {
    _instance._backendMode = _defaultUseMediaTimelineBridge
        ? HydraCamApiBackendMode.mediaTimelineBridge
        : HydraCamApiBackendMode.legacyMobo;
    _instance._legacyBaseUrl = _defaultLegacyBaseUrl;
    _instance._mediaTimelineBaseUrl = _defaultMediaTimelineBaseUrl;
    _instance._mediaTimelineBridgeRetryMaxAttempts = 7;
    _instance._mediaTimelineBridgeRetryInitialDelay =
        const Duration(seconds: 1);
  }

  void cancelInFlightRequests() {
    _httpClient.close();
    _httpClient = http.Client();
    LogService.instance.registerLog("Cancelled in-flight API requests.");
  }

  Uri _apiUri(
    String endpoint, {
    HydraCamApiBackendMode? backendMode,
  }) {
    final baseUri = Uri.parse(_baseUrlForMode(backendMode));
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

  Uri _mediaTimelineApiPathUri(
    String path, {
    Map<String, String?> queryParameters = const {},
  }) {
    final baseUri = Uri.parse(_baseUrlForMode(
      HydraCamApiBackendMode.mediaTimelineBridge,
    ));
    final basePath = baseUri.path.endsWith("/")
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final normalizedPath = path.startsWith("/") ? path : "$basePath/$path";
    final effectiveQueryParameters = <String, String>{};
    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value != null) {
        effectiveQueryParameters[entry.key] = value;
      }
    }
    return baseUri.replace(
      path: normalizedPath,
      queryParameters:
          effectiveQueryParameters.isEmpty ? null : effectiveQueryParameters,
    );
  }

  String _baseUrlForMode(HydraCamApiBackendMode? backendMode) {
    switch (backendMode ?? HydraCamApiBackendMode.legacyMobo) {
      case HydraCamApiBackendMode.legacyMobo:
        return _legacyBaseUrl;
      case HydraCamApiBackendMode.mediaTimelineBridge:
        return _mediaTimelineBaseUrl;
    }
  }

  bool get _usesMediaTimelineBridge =>
      _backendMode == HydraCamApiBackendMode.mediaTimelineBridge;

  String get _createSessionEndpoint => _usesMediaTimelineBridge
      ? HydraCamBridgeSessionContract.createSessionEndpoint
      : HydraCamSessionContract.createSessionEndpoint;

  String get _endSessionEndpoint => _usesMediaTimelineBridge
      ? HydraCamBridgeSessionContract.endSessionEndpoint
      : HydraCamSessionContract.endSessionEndpoint;

  String get _uploadMediaEndpoint => _usesMediaTimelineBridge
      ? HydraCamBridgeSessionContract.uploadMediaEndpoint
      : HydraCamUploadMediaContract.endpoint;

  /// Obtiene las cabeceras comunes, incluyendo `Authorization: Bearer <token>`.
  Future<Map<String, String>> _getHeaders({bool authenticated = true}) async {
    if (!authenticated) {
      return {"Content-Type": "application/json"};
    }
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
    String endpoint,
    Map<String, dynamic> body, {
    HydraCamApiBackendMode? backendMode,
    bool authenticated = true,
  }) async {
    final resolvedBackendMode = backendMode ?? _backendMode;
    for (var attempt = 1;; attempt += 1) {
      try {
        final headers = await _getHeaders(authenticated: authenticated);
        final uri = _apiUri(endpoint, backendMode: resolvedBackendMode);
        final response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
          return _decodeSuccessfulPostResponse(endpoint, response.body);
        } else {
          LogService.instance
              .registerLog("POST $endpoint failed: ${response.body}");
          return null;
        }
      } catch (e) {
        if (_shouldRetryMediaTimelineBridgeRequest(
          backendMode: resolvedBackendMode,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-timeline bridge POST after transient failure "
            "(attempt $attempt/$_mediaTimelineBridgeRetryMaxAttempts): $e",
          );
          await _waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance.registerLog("Error on POST $endpoint: $e");
        return null;
      }
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
        _createSessionEndpoint,
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

      final backendMode = _backendMode;
      final headers =
          await _getHeaders(authenticated: !_usesMediaTimelineBridge);

      // Make the POST request
      final uri = _apiUri(endpoint, backendMode: backendMode);
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

  Future<HydraCamDirectUploadStart?> startBridgeDirectUpload({
    required String sessionGuid,
    required String uploadToken,
    required String filename,
    required bool isPhoto,
    required String deviceId,
    DateTime? capturedAt,
    DateTime? receivedAt,
    int? sizeBytes,
    String? mimeType,
  }) async {
    final normalizedSessionGuid = _normalizedUploadSessionGuid(sessionGuid);
    final normalizedUploadToken = _optionalString(uploadToken);
    final normalizedFilename = _optionalString(filename);
    if (normalizedSessionGuid == null ||
        normalizedUploadToken == null ||
        normalizedFilename == null) {
      LogService.instance.registerLog(
          "Cannot start bridge direct upload: missing session, token, or filename.");
      return null;
    }

    final deviceIdForUpload = _optionalString(deviceId);
    final mimeTypeForUpload = _optionalString(mimeType);
    final endpoint =
        hydracamBridgeDirectUploadStartEndpoint(normalizedSessionGuid);
    final uri = _apiUri(
      endpoint,
      backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
    );
    final body = <String, dynamic>{
      "filename": normalizedFilename,
      "kind": isPhoto ? "photo" : "video",
      if (deviceIdForUpload != null) "deviceId": deviceIdForUpload,
      if (capturedAt != null)
        "capturedAt": capturedAt.toUtc().toIso8601String(),
      if (receivedAt != null)
        "receivedAt": receivedAt.toUtc().toIso8601String(),
      if (sizeBytes != null) "size": sizeBytes,
      if (mimeTypeForUpload != null) "mimeType": mimeTypeForUpload,
    };

    for (var attempt = 1;; attempt += 1) {
      try {
        final response = await _httpClient.post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $normalizedUploadToken",
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          LogService.instance.registerLog(
              "Failed to start bridge direct upload: ${response.body}");
          return null;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          LogService.instance.registerLog(
              "Failed to start bridge direct upload: unexpected response $decoded");
          return null;
        }
        return HydraCamDirectUploadStart.fromJson(_asStringKeyedMap(decoded));
      } catch (e) {
        if (_shouldRetryMediaTimelineBridgeRequest(
          backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-timeline bridge direct upload start after transient "
            "failure (attempt $attempt/$_mediaTimelineBridgeRetryMaxAttempts): $e",
          );
          await _waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance
            .registerLog("Error starting bridge direct upload: $e");
        return null;
      }
    }
  }

  Future<bool> _uploadMediaViaMediaTimelineDirectStorage({
    required String sessionGuid,
    required String uploadToken,
    required File file,
    required bool isPhoto,
    required String slaveDeviceId,
    required DateTime captureDate,
    required DateTime receivedDate,
    required int fileLength,
    required Duration? effectiveVideoDuration,
    required Function(double)? onProgress,
    required Function(HydraCamUploadResult)? onUploadResult,
  }) async {
    try {
      final filename = file.path.split("/").last;
      final contentType = _uploadMediaContentType(file, isPhoto: isPhoto);
      final directStart = await startBridgeDirectUpload(
        sessionGuid: sessionGuid,
        uploadToken: uploadToken,
        filename: filename,
        isPhoto: isPhoto,
        deviceId: slaveDeviceId,
        capturedAt: captureDate,
        receivedAt: receivedDate,
        sizeBytes: fileLength,
        mimeType: contentType.toString(),
      );
      if (directStart == null ||
          directStart.preferredStorage != "object-storage") {
        return false;
      }

      final multipartStart = await _startMediaStorageMultipartUpload(
        path: directStart.mediaStorage.startPath,
        filename: filename,
        contentType: contentType.toString(),
        eventId: directStart.eventId,
      );
      if (multipartStart == null) {
        return false;
      }

      final uploadedPart = await _uploadMediaStorageMultipartPart(
        path: directStart.mediaStorage.uploadPartPath,
        multipartStart: multipartStart,
        file: file,
        fileLength: fileLength,
        onProgress: onProgress,
      );
      if (uploadedPart == null) {
        return false;
      }

      final storageComplete = await _completeMediaStorageMultipartUpload(
        path: directStart.mediaStorage.completeObjectPath,
        multipartStart: multipartStart,
        uploadedPart: uploadedPart,
        filename: filename,
        isPhoto: isPhoto,
      );
      if (storageComplete == null) {
        return false;
      }

      final bridgeComplete = await _completeBridgeDirectUpload(
        path: directStart.mediaStorage.completeBridgePath,
        uploadToken: uploadToken,
        sessionGuid: sessionGuid,
        fileId: storageComplete.fileId,
        locator: storageComplete.locator,
        filename: filename,
        isPhoto: isPhoto,
        slaveDeviceId: slaveDeviceId,
        captureDate: captureDate,
        receivedDate: receivedDate,
        fileLength: fileLength,
        effectiveVideoDuration: effectiveVideoDuration,
        mimeType: contentType.toString(),
      );
      if (bridgeComplete == null) {
        return false;
      }

      onUploadResult?.call(
        HydraCamUploadResult(
          eventId: bridgeComplete.eventId,
          sessionGuid: sessionGuid,
          files: [
            HydraCamUploadFileResult(
              fileId: bridgeComplete.fileId,
              filename: filename,
              kind: isPhoto ? "photo" : "video",
              eventId: bridgeComplete.eventId,
              sessionGuid: sessionGuid,
              storage: "object-storage",
            ),
          ],
        ),
      );
      LogService.instance
          .registerLog("Media uploaded through media-timeline object storage");
      return true;
    } catch (e) {
      LogService.instance
          .registerLog("Direct media-timeline object upload failed: $e");
      return false;
    }
  }

  Future<_MediaStorageMultipartStart?> _startMediaStorageMultipartUpload({
    required String path,
    required String filename,
    required String contentType,
    required String eventId,
  }) async {
    final response = await _postMediaTimelineJson(
      _mediaTimelineApiPathUri(path),
      {
        "filename": filename,
        "contentType": contentType,
        "eventId": eventId,
      },
    );
    if (response == null) {
      return null;
    }
    return _MediaStorageMultipartStart.fromJson(response);
  }

  Future<_MediaStorageUploadedPart?> _uploadMediaStorageMultipartPart({
    required String path,
    required _MediaStorageMultipartStart multipartStart,
    required File file,
    required int fileLength,
    required Function(double)? onProgress,
  }) async {
    final uri = _mediaTimelineApiPathUri(
      path,
      queryParameters: {
        "key": multipartStart.key,
        "uploadId": multipartStart.uploadId,
        "partNumber": "1",
      },
    );
    for (var attempt = 1;; attempt += 1) {
      try {
        var uploadedBytes = 0;
        final request = http.StreamedRequest("PUT", uri)
          ..headers["Content-Type"] = "application/octet-stream"
          ..contentLength = fileLength;
        final streamedResponseFuture = _httpClient.send(request);
        await request.sink.addStream(
          file.openRead().transform(
            StreamTransformer.fromHandlers(
              handleData: (chunk, sink) {
                uploadedBytes += chunk.length;
                onProgress?.call(uploadedBytes / fileLength);
                sink.add(chunk);
              },
            ),
          ),
        );
        await request.sink.close();
        final streamedResponse = await streamedResponseFuture;
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode != 200) {
          LogService.instance.registerLog(
              "Media storage part upload failed: ${response.body}");
          return null;
        }
        return _MediaStorageUploadedPart.fromJson(
          _asStringKeyedMap(jsonDecode(response.body)),
        );
      } catch (e) {
        if (_shouldRetryMediaTimelineBridgeRequest(
          backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-storage part upload after transient failure "
            "(attempt $attempt/$_mediaTimelineBridgeRetryMaxAttempts): $e",
          );
          await _waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance.registerLog("Media storage part upload failed: $e");
        return null;
      }
    }
  }

  Future<_MediaStorageComplete?> _completeMediaStorageMultipartUpload({
    required String path,
    required _MediaStorageMultipartStart multipartStart,
    required _MediaStorageUploadedPart uploadedPart,
    required String filename,
    required bool isPhoto,
  }) async {
    final response = await _postMediaTimelineJson(
      _mediaTimelineApiPathUri(path),
      {
        "key": multipartStart.key,
        "uploadId": multipartStart.uploadId,
        "filename": filename,
        "kind": isPhoto ? "photo" : "video",
        "parts": [uploadedPart.toJson()],
      },
    );
    if (response == null) {
      return null;
    }
    return _MediaStorageComplete.fromJson(response);
  }

  Future<_HydraCamBridgeCompletedUpload?> _completeBridgeDirectUpload({
    required String path,
    required String uploadToken,
    required String sessionGuid,
    required String fileId,
    required String locator,
    required String filename,
    required bool isPhoto,
    required String slaveDeviceId,
    required DateTime captureDate,
    required DateTime receivedDate,
    required int fileLength,
    required Duration? effectiveVideoDuration,
    required String mimeType,
  }) async {
    final response = await _postMediaTimelineJson(
      _mediaTimelineApiPathUri(path),
      {
        "fileId": fileId,
        "locator": locator,
        "metadata": {
          "sessionGuid": sessionGuid,
          "deviceId": slaveDeviceId,
          "filename": filename,
          "kind": isPhoto ? "photo" : "video",
          "mimeType": mimeType,
          "sourceBytes": fileLength,
          "capturedAt": captureDate.toUtc().toIso8601String(),
          "receivedAt": receivedDate.toUtc().toIso8601String(),
          if (effectiveVideoDuration != null)
            "durationSeconds": effectiveVideoDuration.inMilliseconds / 1000,
        },
      },
      headers: {
        "Authorization": "Bearer $uploadToken",
      },
    );
    if (response == null) {
      return null;
    }
    return _HydraCamBridgeCompletedUpload.fromJson(response);
  }

  Future<Map<String, dynamic>?> _postMediaTimelineJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    for (var attempt = 1;; attempt += 1) {
      try {
        final response = await _httpClient.post(
          uri,
          headers: {
            "Content-Type": "application/json",
            ...headers,
          },
          body: jsonEncode(body),
        );
        if (response.statusCode != 200) {
          LogService.instance
              .registerLog("Media-timeline JSON POST failed: ${response.body}");
          return null;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          LogService.instance.registerLog(
              "Media-timeline JSON POST returned unexpected response: $decoded");
          return null;
        }
        return _asStringKeyedMap(decoded);
      } catch (e) {
        if (_shouldRetryMediaTimelineBridgeRequest(
          backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-timeline JSON POST after transient failure "
            "(attempt $attempt/$_mediaTimelineBridgeRetryMaxAttempts): $e",
          );
          await _waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance.registerLog("Media-timeline JSON POST failed: $e");
        return null;
      }
    }
  }

  /// End a session
  Future<bool> endSession(String sessionGuid) async {
    try {
      final backendMode = _backendMode;
      final response = await _post(
        hydracamApiEndpoint(
          _endSessionEndpoint,
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
    String? mediaTimelineUploadToken,
    Function(String)? onFailureReason,
    Function(HydraCamUploadResult)? onUploadResult,
  }) async {
    try {
      final normalizedSessionGuid = _normalizedUploadSessionGuid(sessionGuid);
      if (normalizedSessionGuid == null) {
        final failureReason =
            "Upload session GUID is invalid: ${_invalidSessionGuidLabel(sessionGuid)}";
        return _failUpload(
          failureReason,
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $failureReason",
        );
      }

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

      final backendMode = _backendMode;
      if (backendMode == HydraCamApiBackendMode.mediaTimelineBridge &&
          _optionalString(mediaTimelineUploadToken) != null) {
        final directUploadSucceeded =
            await _uploadMediaViaMediaTimelineDirectStorage(
          sessionGuid: normalizedSessionGuid,
          uploadToken: mediaTimelineUploadToken!,
          file: file,
          isPhoto: isPhoto,
          slaveDeviceId: slaveDeviceId,
          captureDate: captureDate,
          receivedDate: receivedDate,
          fileLength: fileLength,
          effectiveVideoDuration: effectiveVideoDuration,
          onProgress: onProgress,
          onUploadResult: onUploadResult,
        );
        if (directUploadSucceeded) {
          return true;
        }
        LogService.instance.registerLog(
          "Falling back to media-timeline bridge compatibility upload.",
        );
      }

      final headers = backendMode == HydraCamApiBackendMode.legacyMobo
          ? await _getHeaders()
          : <String, String>{};
      final appMetadata = await _getUploadAppMetadata();
      final uri = _apiUri(
        hydracamApiEndpoint(
          _uploadMediaEndpoint,
          queryParameters: {
            HydraCamUploadMediaContract.querySessionGuid: normalizedSessionGuid,
            HydraCamUploadMediaContract.queryIsPhoto: isPhoto.toString(),
          },
        ),
        backendMode: backendMode,
      );

      Future<http.Response> sendUploadAttempt() async {
        final request = http.MultipartRequest(
          HydraCamUploadMediaContract.method,
          uri,
        )
          ..headers.addAll(headers)
          ..fields[HydraCamUploadMediaContract.fieldSlaveDeviceId] =
              slaveDeviceId
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
            contentType: _uploadMediaContentType(file, isPhoto: isPhoto),
          ),
        );

        final streamedResponse = await _httpClient.send(request);
        return http.Response.fromStream(streamedResponse);
      }

      late final http.Response response;
      for (var attempt = 1;; attempt += 1) {
        try {
          response = await sendUploadAttempt();
          break;
        } catch (e) {
          if (_shouldRetryMediaTimelineBridgeRequest(
            backendMode: backendMode,
            attempt: attempt,
            error: e,
          )) {
            LogService.instance.registerLog(
              "Retrying media-timeline bridge upload after transient failure "
              "(attempt $attempt/$_mediaTimelineBridgeRetryMaxAttempts): $e",
            );
            await _waitBeforeMediaTimelineBridgeRetry(attempt);
            continue;
          }
          return _failUpload(
            "Error uploading media: $e",
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $e",
          );
        }
      }

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
        _notifyUploadResult(response.body, onUploadResult);
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

  String? _normalizedUploadSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    final lowerSessionGuid = normalizedSessionGuid.toLowerCase();
    if (normalizedSessionGuid.isEmpty ||
        lowerSessionGuid.startsWith("local-") ||
        lowerSessionGuid == "null" ||
        lowerSessionGuid == "undefined") {
      return null;
    }
    return normalizedSessionGuid;
  }

  String _invalidSessionGuidLabel(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    return normalizedSessionGuid.isEmpty ? "<blank>" : normalizedSessionGuid;
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

  MediaType _uploadMediaContentType(File file, {required bool isPhoto}) {
    if (!isPhoto) {
      return MediaType("video", "mp4");
    }

    final extension = file.path.split(".").last.toLowerCase();
    if (extension == "png") {
      return MediaType("image", "png");
    }
    if (extension == "heic" || extension == "heif") {
      return MediaType("image", "heic");
    }
    return MediaType("image", "jpeg");
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

  void _notifyUploadResult(
    String responseBody,
    Function(HydraCamUploadResult)? onUploadResult,
  ) {
    if (onUploadResult == null) {
      return;
    }

    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty || trimmedBody == _legacyUploadSuccessBody) {
      return;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is Map) {
        onUploadResult(
          HydraCamUploadResult.fromJson(_asStringKeyedMap(decoded)),
        );
      }
    } catch (e) {
      LogService.instance
          .registerLog("Upload identity metadata unavailable: $e");
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

  bool _shouldRetryMediaTimelineBridgeRequest({
    required HydraCamApiBackendMode backendMode,
    required int attempt,
    required Object error,
  }) {
    return backendMode == HydraCamApiBackendMode.mediaTimelineBridge &&
        attempt < _mediaTimelineBridgeRetryMaxAttempts &&
        _isTransientBridgeError(error);
  }

  bool _isTransientBridgeError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is http.ClientException || error is HttpException) {
      final message = error.toString().toLowerCase();
      return message.contains("connection refused") ||
          message.contains("connection reset") ||
          message.contains("connection closed") ||
          message.contains("connection aborted") ||
          message.contains("connection timed out") ||
          message.contains("operation timed out") ||
          message.contains("failed host lookup");
    }
    return false;
  }

  Future<void> _waitBeforeMediaTimelineBridgeRetry(int attempt) async {
    final delay = _mediaTimelineBridgeRetryDelay(attempt);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  Duration _mediaTimelineBridgeRetryDelay(int attempt) {
    var delay = _mediaTimelineBridgeRetryInitialDelay;
    for (var index = 1; index < attempt; index += 1) {
      delay *= 2;
    }
    const maxDelay = Duration(seconds: 5);
    return delay > maxDelay ? maxDelay : delay;
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
