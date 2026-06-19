import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;

import "../models/hls_stream_bundle.dart";

class HlsStreamUploadResult {
  const HlsStreamUploadResult({
    required this.eventId,
    required this.sessionGuid,
    required this.fileId,
    required this.filename,
  });

  final String eventId;
  final String sessionGuid;
  final String fileId;
  final String filename;

  factory HlsStreamUploadResult.fromJson(Map<String, dynamic> json) {
    final stream = json["stream"];
    if (stream is! Map<String, dynamic>) {
      throw const FormatException(
          "HLS upload response is missing stream data.");
    }
    final eventId = json["eventId"];
    final sessionGuid = json["sessionGuid"];
    final fileId = stream["fileId"];
    final filename = stream["filename"];
    if (eventId is! String ||
        sessionGuid is! String ||
        fileId is! String ||
        filename is! String) {
      throw const FormatException("HLS upload response has invalid fields.");
    }
    return HlsStreamUploadResult(
      eventId: eventId,
      sessionGuid: sessionGuid,
      fileId: fileId,
      filename: filename,
    );
  }
}

class HlsStreamTimingMetadata {
  const HlsStreamTimingMetadata({
    this.syncConfidence,
    this.videoTimeZeroSharedClockNanos,
    this.video,
    this.audio,
    this.cameraTiming,
    this.ntp,
  }) : rawJson = null;

  const HlsStreamTimingMetadata.rawJson(this.rawJson)
      : syncConfidence = null,
        videoTimeZeroSharedClockNanos = null,
        video = null,
        audio = null,
        cameraTiming = null,
        ntp = null;

  final String? rawJson;
  final String? syncConfidence;
  final int? videoTimeZeroSharedClockNanos;
  final Map<String, Object?>? video;
  final Map<String, Object?>? audio;
  final Map<String, Object?>? cameraTiming;
  final Map<String, Object?>? ntp;

  Map<String, Object?> toJson() {
    return {
      if (syncConfidence != null) "syncConfidence": syncConfidence,
      if (videoTimeZeroSharedClockNanos != null)
        "videoTimeZeroSharedClockNanos": videoTimeZeroSharedClockNanos,
      if (video != null) "video": video,
      if (audio != null) "audio": audio,
      if (cameraTiming != null) "cameraTiming": cameraTiming,
      if (ntp != null) "ntp": ntp,
    };
  }

  String toWireJsonString() {
    final raw = rawJson;
    return raw ?? jsonEncode(toJson());
  }
}

class HlsStreamUploadService {
  HlsStreamUploadService({
    String baseApiUrl = const String.fromEnvironment(
      "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL",
      defaultValue: "http://127.0.0.1:3001/api",
    ),
    http.Client? httpClient,
  })  : _baseApiUrl = baseApiUrl,
        _httpClient = httpClient ?? http.Client();

  final String _baseApiUrl;
  final http.Client _httpClient;

  Future<HlsStreamUploadResult> uploadBundle({
    required String sessionGuid,
    required HlsStreamBundle bundle,
    required String deviceId,
    required DateTime capturedAt,
    String? recordingId,
    HlsStreamTimingMetadata? timingMetadata,
  }) async {
    final request = http.MultipartRequest(
      "POST",
      _endpointUri(
        "hydracam-bridge/compat/sessions/upload-hls",
        {"sessionGuid": sessionGuid},
      ),
    )
      ..fields["deviceId"] = deviceId
      ..fields["capturedAt"] = capturedAt.toUtc().toIso8601String()
      ..fields["fixedCamera"] = "true";

    if (recordingId != null && recordingId.trim().isNotEmpty) {
      request.fields["recordingId"] = recordingId.trim();
    }
    if (timingMetadata != null) {
      request.fields["nativeTimingMetadataJson"] =
          timingMetadata.toWireJsonString();
    }
    final targetDuration = bundle.targetDuration;
    if (targetDuration != null) {
      request.fields["targetDurationSeconds"] =
          targetDuration.inSeconds.toString();
    }

    request.files.add(await _multipartFile("playlist", bundle.playlist));
    final initSegment = bundle.initSegment;
    if (initSegment != null) {
      request.files.add(await _multipartFile("init", initSegment));
    }
    for (final chunk in bundle.chunks) {
      request.files.add(await _multipartFile("chunks", chunk));
    }

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        "HLS upload failed (${response.statusCode}): ${response.body}",
        uri: request.url,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("HLS upload response is not a JSON object.");
    }
    return HlsStreamUploadResult.fromJson(decoded);
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

  Future<http.MultipartFile> _multipartFile(String field, File file) async {
    final length = await file.length();
    return http.MultipartFile(
      field,
      file.openRead(),
      length,
      filename: file.uri.pathSegments.last,
    );
  }
}
