part of "../hydracam_api_service.dart";

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
