import "dart:io";

import "package:flutter/services.dart";

import "../models/hls_stream_bundle.dart";
import "../models/json_value_parsers.dart";

/// A single recordable video mode the device camera exposes.
class FixedCameraHlsCameraMode {
  const FixedCameraHlsCameraMode({
    required this.cameraId,
    required this.width,
    required this.height,
    required this.maxFps,
    required this.lensFacing,
  });

  final String cameraId;
  final int width;
  final int height;
  final int maxFps;
  final String lensFacing;

  int get pixelCount => width * height;

  String get label =>
      "${width}x$height @${maxFps}fps · $lensFacing (cam $cameraId)";

  @override
  bool operator ==(Object other) =>
      other is FixedCameraHlsCameraMode &&
      other.cameraId == cameraId &&
      other.width == width &&
      other.height == height &&
      other.maxFps == maxFps &&
      other.lensFacing == lensFacing;

  @override
  int get hashCode => Object.hash(cameraId, width, height, maxFps, lensFacing);

  static FixedCameraHlsCameraMode? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final cameraId = value["cameraId"];
    final width = value["width"];
    final height = value["height"];
    if (cameraId is! String || width is! int || height is! int) {
      return null;
    }
    return FixedCameraHlsCameraMode(
      cameraId: cameraId,
      width: width,
      height: height,
      maxFps: value["maxFps"] is int ? value["maxFps"] as int : 30,
      lensFacing: value["lensFacing"] is String
          ? value["lensFacing"] as String
          : "unknown",
    );
  }
}

class FixedCameraHlsCapabilities {
  const FixedCameraHlsCapabilities({
    required this.platform,
    required this.channelAvailable,
    required this.nativeRecorderImplemented,
    required this.cameraRecorderImplemented,
    required this.requiresCameraHardware,
    required this.supportsHlsUpload,
    required this.supportedMimeTypes,
    this.recorderMode,
    this.supportedRecorderModes = const [],
    this.cameraIds = const [],
    this.cameraModes = const [],
    this.androidSdk,
    this.outputDirectoryPath,
    this.reason,
  });

  final String platform;
  final bool channelAvailable;
  final bool nativeRecorderImplemented;
  final bool cameraRecorderImplemented;
  final bool requiresCameraHardware;
  final bool supportsHlsUpload;
  final List<String> supportedMimeTypes;
  final String? recorderMode;
  final List<String> supportedRecorderModes;
  final List<String> cameraIds;
  final List<FixedCameraHlsCameraMode> cameraModes;
  final int? androidSdk;
  final String? outputDirectoryPath;
  final String? reason;

  bool get canRecordNativeHls => channelAvailable && nativeRecorderImplemented;
  bool get canRecordCameraHls => channelAvailable && cameraRecorderImplemented;

  /// Modes for [cameraId], largest pixel count first.
  List<FixedCameraHlsCameraMode> modesForCamera(String cameraId) {
    final modes = cameraModes
        .where((mode) => mode.cameraId == cameraId)
        .toList()
      ..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
    return modes;
  }

  /// The highest-resolution mode for [cameraId], or null if none are known.
  FixedCameraHlsCameraMode? highestModeForCamera(String cameraId) {
    final modes = modesForCamera(cameraId);
    return modes.isEmpty ? null : modes.first;
  }

  factory FixedCameraHlsCapabilities.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const FixedCameraHlsCapabilities.unsupported(
        reason: "Fixed-camera HLS native capabilities were empty.",
      );
    }

    return FixedCameraHlsCapabilities(
      platform: stringOrFallback(map["platform"], fallback: "unknown"),
      channelAvailable: boolOrFallback(map["channelAvailable"]),
      nativeRecorderImplemented:
          boolOrFallback(map["nativeRecorderImplemented"]),
      cameraRecorderImplemented: boolOrFallback(
        map["cameraRecorderImplemented"],
      ),
      requiresCameraHardware:
          boolOrFallback(map["requiresCameraHardware"], fallback: true),
      supportsHlsUpload: boolOrFallback(map["supportsHlsUpload"]),
      supportedMimeTypes: _stringListValue(map["supportedMimeTypes"]),
      recorderMode:
          map["recorderMode"] is String ? map["recorderMode"] as String : null,
      supportedRecorderModes: _stringListValue(map["supportedRecorderModes"]),
      cameraIds: _stringListValue(map["cameraIds"]),
      cameraModes: _cameraModesValue(map["cameraModes"]),
      androidSdk: _intValue(map["androidSdk"]),
      outputDirectoryPath: map["outputDirectoryPath"] is String
          ? map["outputDirectoryPath"] as String
          : null,
      reason: map["reason"] is String ? map["reason"] as String : null,
    );
  }

  const factory FixedCameraHlsCapabilities.unsupported({
    String platform,
    String? reason,
  }) = _UnsupportedFixedCameraHlsCapabilities;

  static List<FixedCameraHlsCameraMode> _cameraModesValue(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .map(FixedCameraHlsCameraMode.fromMap)
        .whereType<FixedCameraHlsCameraMode>()
        .toList(growable: false);
  }
}

class _UnsupportedFixedCameraHlsCapabilities
    extends FixedCameraHlsCapabilities {
  const _UnsupportedFixedCameraHlsCapabilities({
    super.platform = "unknown",
    super.reason,
  }) : super(
          channelAvailable: false,
          nativeRecorderImplemented: false,
          cameraRecorderImplemented: false,
          requiresCameraHardware: true,
          supportsHlsUpload: true,
          supportedMimeTypes: const [],
        );
}

enum FixedCameraHlsRecordingState {
  recording,
  finalized,
  failed,
  unknown;

  static FixedCameraHlsRecordingState fromString(Object? value) {
    return switch (value) {
      "recording" => FixedCameraHlsRecordingState.recording,
      "finalized" => FixedCameraHlsRecordingState.finalized,
      "failed" => FixedCameraHlsRecordingState.failed,
      _ => FixedCameraHlsRecordingState.unknown,
    };
  }
}

class FixedCameraHlsRecordingRequest {
  const FixedCameraHlsRecordingRequest({
    required this.sessionGuid,
    required this.deviceId,
    required this.recordingId,
    this.cameraId,
    this.targetDurationSeconds = 2,
    this.width = 1920,
    this.height = 1080,
    this.frameRate = 30,
    this.includeAudio = true,
  });

  final String sessionGuid;
  final String deviceId;
  final String recordingId;
  final String? cameraId;
  final int targetDurationSeconds;
  final int width;
  final int height;
  final int frameRate;
  final bool includeAudio;

  Map<String, Object?> toMap() {
    return {
      "sessionGuid": sessionGuid,
      "deviceId": deviceId,
      "recordingId": recordingId,
      if (cameraId != null) "cameraId": cameraId,
      "targetDurationSeconds": targetDurationSeconds,
      "width": width,
      "height": height,
      "frameRate": frameRate,
      "includeAudio": includeAudio,
    };
  }
}

class FixedCameraHlsRecordingResult {
  const FixedCameraHlsRecordingResult({
    required this.recordingId,
    required this.recordingDirectoryPath,
    required this.state,
    this.playlistPath,
    this.initPath,
    this.chunkPaths = const [],
    this.durationSeconds,
    this.targetDurationSeconds,
    this.startedAt,
    this.finalizedAt,
    this.nativeTimingMetadataJson,
  });

  final String recordingId;
  final String recordingDirectoryPath;
  final FixedCameraHlsRecordingState state;
  final String? playlistPath;
  final String? initPath;
  final List<String> chunkPaths;
  final double? durationSeconds;
  final int? targetDurationSeconds;
  final DateTime? startedAt;
  final DateTime? finalizedAt;
  final String? nativeTimingMetadataJson;

  factory FixedCameraHlsRecordingResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      throw const FormatException(
          "Fixed-camera HLS recording result was empty.");
    }

    return FixedCameraHlsRecordingResult(
      recordingId: _requiredString(map["recordingId"], "recordingId"),
      recordingDirectoryPath: _requiredString(
        map["recordingDirectoryPath"],
        "recordingDirectoryPath",
      ),
      state: FixedCameraHlsRecordingState.fromString(map["state"]),
      playlistPath: _optionalString(map["playlistPath"]),
      initPath: _optionalString(map["initPath"]),
      chunkPaths: _stringListValue(map["chunkPaths"]),
      durationSeconds: _doubleValue(map["durationSeconds"]),
      targetDurationSeconds: _intValue(map["targetDurationSeconds"]),
      startedAt: _dateTimeValue(map["startedAt"]),
      finalizedAt: _dateTimeValue(map["finalizedAt"]),
      nativeTimingMetadataJson: _optionalString(
        map["nativeTimingMetadataJson"],
      ),
    );
  }

  Future<HlsStreamBundle> toHlsStreamBundle() {
    if (state != FixedCameraHlsRecordingState.finalized) {
      throw StateError(
        "Fixed-camera HLS recording must be finalized before upload.",
      );
    }
    final playlist = playlistPath;
    if (playlist == null || playlist.isEmpty) {
      throw StateError(
          "Fixed-camera HLS recording is missing a playlist path.");
    }
    final playlistFile = File(playlist);
    return HlsStreamBundle.fromDirectory(
      playlistFile.parent,
      playlistName: playlistFile.uri.pathSegments.last,
    );
  }

  static String _requiredString(Object? value, String fieldName) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException("$fieldName is required.");
  }

  static String? _optionalString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  static double? _doubleValue(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    return value is double ? value : null;
  }

  static DateTime? _dateTimeValue(Object? value) {
    return value is String ? DateTime.tryParse(value) : null;
  }
}

class FixedCameraHlsRecorderService {
  FixedCameraHlsRecorderService({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = "hydracamv2/fixed_camera_hls";

  final MethodChannel _channel;

  Future<FixedCameraHlsCapabilities> getCapabilities() async {
    try {
      final response =
          await _channel.invokeMethod<Map<dynamic, dynamic>>("getCapabilities");
      return FixedCameraHlsCapabilities.fromMap(response);
    } on MissingPluginException catch (error) {
      return FixedCameraHlsCapabilities.unsupported(
        reason: "Fixed-camera HLS native channel is not available: "
            "${error.message ?? error.toString()}",
      );
    }
  }

  Future<FixedCameraHlsRecordingResult> startRecording(
    FixedCameraHlsRecordingRequest request,
  ) async {
    final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      "startRecording",
      request.toMap(),
    );
    return FixedCameraHlsRecordingResult.fromMap(response);
  }

  Future<FixedCameraHlsRecordingResult> stopRecording(
      String recordingId) async {
    final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      "stopRecording",
      {"recordingId": recordingId},
    );
    return FixedCameraHlsRecordingResult.fromMap(response);
  }
}

int? _intValue(Object? value) {
  return value is int ? value : null;
}

List<String> _stringListValue(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value.whereType<String>().toList(growable: false);
}
