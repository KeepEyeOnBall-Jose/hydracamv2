import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;
import "package:http_parser/http_parser.dart";

class WearableReplayUploadResult {
  const WearableReplayUploadResult({
    required this.eventId,
    required this.sessionGuid,
    required this.trackCount,
    required this.sampleFileCount,
    required this.calibrationCount,
    required this.markerCount,
    required this.povRecordingCount,
    required this.povMediaCount,
    required this.feedbackCount,
  });

  final String eventId;
  final String sessionGuid;
  final int trackCount;
  final int sampleFileCount;
  final int calibrationCount;
  final int markerCount;
  final int povRecordingCount;
  final int povMediaCount;
  final int feedbackCount;

  factory WearableReplayUploadResult.fromJson(Map<String, dynamic> json) {
    final eventId = json["eventId"];
    final sessionGuid = json["sessionGuid"];
    if (eventId is! String || sessionGuid is! String) {
      throw const FormatException(
        "Wearable replay upload response has invalid identity fields.",
      );
    }
    return WearableReplayUploadResult(
      eventId: eventId,
      sessionGuid: sessionGuid,
      trackCount: _intValue(json["trackCount"]),
      sampleFileCount: _intValue(json["sampleFileCount"]),
      calibrationCount: _intValue(json["calibrationCount"]),
      markerCount: _intValue(json["markerCount"]),
      povRecordingCount: _intValue(json["povRecordingCount"]),
      povMediaCount: _intValue(json["povMediaCount"]),
      feedbackCount: _intValue(json["feedbackCount"]),
    );
  }
}

class WearableReplayUploadService {
  WearableReplayUploadService({
    String baseApiUrl = const String.fromEnvironment(
      "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL",
      defaultValue: "http://127.0.0.1:3001/api",
    ),
    http.Client? httpClient,
  })  : _baseApiUrl = baseApiUrl,
        _httpClient = httpClient ?? http.Client();

  final String _baseApiUrl;
  final http.Client _httpClient;

  Future<WearableReplayUploadResult> uploadManifest({
    required String sessionGuid,
    required File manifestFile,
    required String pairedHydraCamDeviceId,
    required String participantId,
  }) async {
    final manifest = await _readManifest(manifestFile);
    final request = http.MultipartRequest(
      "POST",
      _endpointUri(
        "hydracam-bridge/compat/sessions/upload-wearables",
        {"sessionGuid": sessionGuid},
      ),
    )
      ..fields["pairedHydraCamDeviceId"] = pairedHydraCamDeviceId
      ..fields["participantId"] = participantId
      ..fields["manifestJson"] = jsonEncode(manifest);

    await _addFiles(request, "trackFiles", manifest["trackFiles"]);
    await _addFiles(request, "sampleFiles", manifest["sampleFiles"]);
    await _addFiles(
      request,
      "calibrationFiles",
      manifest["calibrationFiles"],
    );
    await _addFiles(request, "markerFiles", manifest["markerFiles"]);
    await _addFiles(
      request,
      "povRecordingFiles",
      manifest["povRecordingFiles"],
    );
    await _addFiles(request, "povMediaFiles", manifest["povMediaFiles"]);
    await _addFiles(request, "feedbackFiles", manifest["feedbackFiles"]);

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        "Wearable replay upload failed (${response.statusCode}): "
        "${response.body}",
        uri: request.url,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        "Wearable replay upload response is not a JSON object.",
      );
    }
    return WearableReplayUploadResult.fromJson(decoded);
  }

  Future<Map<String, dynamic>> _readManifest(File manifestFile) async {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        "Wearable replay manifest is not a JSON object.",
      );
    }
    return decoded;
  }

  Future<void> _addFiles(
    http.MultipartRequest request,
    String field,
    Object? rawPaths,
  ) async {
    if (rawPaths is! Iterable) {
      return;
    }
    for (final rawPath in rawPaths) {
      if (rawPath is! String || rawPath.trim().isEmpty) {
        continue;
      }
      final file = File(rawPath);
      final length = await file.length();
      request.files.add(http.MultipartFile(
        field,
        file.openRead(),
        length,
        filename: file.uri.pathSegments.last,
        contentType: _contentTypeFor(file.path),
      ));
    }
  }

  Uri _endpointUri(String path, Map<String, String> queryParameters) {
    final baseUri = Uri.parse(_baseApiUrl);
    final basePath = baseUri.path.endsWith("/")
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final endpointPath = path.startsWith("/") ? path.substring(1) : path;
    return baseUri.replace(
      path: "$basePath/$endpointPath",
      queryParameters: queryParameters,
    );
  }
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return 0;
}

MediaType _contentTypeFor(String path) {
  final normalized = path.toLowerCase();
  if (normalized.endsWith(".json")) {
    return MediaType("application", "json");
  }
  if (normalized.endsWith(".jsonl") || normalized.endsWith(".ndjson")) {
    return MediaType("application", "x-ndjson");
  }
  if (normalized.endsWith(".mp4") || normalized.endsWith(".m4v")) {
    return MediaType("video", "mp4");
  }
  if (normalized.endsWith(".mov")) {
    return MediaType("video", "quicktime");
  }
  if (normalized.endsWith(".m4a")) {
    return MediaType("audio", "mp4");
  }
  return MediaType("application", "octet-stream");
}
