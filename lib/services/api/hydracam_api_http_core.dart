part of "../hydracam_api_service.dart";

/// Shared low-level HTTP plumbing for the HydraCam backend clients.
///
/// Owns the base URL/backend-mode configuration, auth header injection, the
/// generic GET/POST helpers, the media-timeline bridge retry policy, and the
/// backend success/failure response parsing. Domain clients compose an
/// instance of this core rather than duplicating transport logic.
class HydraCamApiHttpCore {
  HydraCamApiHttpCore({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const int _uploadFailureResponseBodyLogLimit = 300;

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

  http.Client _httpClient;

  void configureBridgeRetryForTests({
    int? maxAttempts,
    Duration? initialDelay,
  }) {
    if (maxAttempts != null) {
      _mediaTimelineBridgeRetryMaxAttempts = maxAttempts;
    }
    if (initialDelay != null) {
      _mediaTimelineBridgeRetryInitialDelay = initialDelay;
    }
  }

  void configureBackendForTests({
    required HydraCamApiBackendMode mode,
    String? baseApiUrl,
  }) {
    _backendMode = mode;
    if (baseApiUrl == null) {
      return;
    }
    switch (mode) {
      case HydraCamApiBackendMode.legacyMobo:
        _legacyBaseUrl = baseApiUrl;
      case HydraCamApiBackendMode.mediaTimelineBridge:
        _mediaTimelineBaseUrl = baseApiUrl;
    }
  }

  void resetBackendForTests() {
    _backendMode = _defaultUseMediaTimelineBridge
        ? HydraCamApiBackendMode.mediaTimelineBridge
        : HydraCamApiBackendMode.legacyMobo;
    _legacyBaseUrl = _defaultLegacyBaseUrl;
    _mediaTimelineBaseUrl = _defaultMediaTimelineBaseUrl;
    _mediaTimelineBridgeRetryMaxAttempts = 7;
    _mediaTimelineBridgeRetryInitialDelay = const Duration(seconds: 1);
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
}
