import "package:flutter/services.dart";

import "../models/json_value_parsers.dart";

class RecordedVideoMetadata {
  const RecordedVideoMetadata({
    required this.width,
    required this.height,
    this.framesPerSecond,
    this.durationMs,
  });

  final int width;
  final int height;
  final double? framesPerSecond;
  final int? durationMs;

  String get framesPerSecondText {
    final fps = framesPerSecond;
    if (fps == null || fps <= 0) {
      return "unknown";
    }
    return fps.toStringAsFixed(fps.truncateToDouble() == fps ? 0 : 2);
  }

  static RecordedVideoMetadata? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return null;
    }
    final width = toIntOrNull(map["width"]);
    final height = toIntOrNull(map["height"]);
    if (width == null || height == null) {
      return null;
    }
    return RecordedVideoMetadata(
      width: width,
      height: height,
      framesPerSecond: toDoubleOrNull(map["framesPerSecond"]),
      durationMs: toIntOrNull(map["durationMs"]),
    );
  }
}

class VideoMetadataService {
  VideoMetadataService._();

  static const MethodChannel _channel =
      MethodChannel("hydracamv2/video_metadata");

  static Future<RecordedVideoMetadata?> inspectVideo(String path) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        "inspectVideo",
        {"path": path},
      );
      return RecordedVideoMetadata.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
