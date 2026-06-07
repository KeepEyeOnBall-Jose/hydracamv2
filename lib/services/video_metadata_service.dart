import "package:flutter/services.dart";

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
    final width = _toInt(map["width"]);
    final height = _toInt(map["height"]);
    if (width == null || height == null) {
      return null;
    }
    return RecordedVideoMetadata(
      width: width,
      height: height,
      framesPerSecond: _toDouble(map["framesPerSecond"]),
      durationMs: _toInt(map["durationMs"]),
    );
  }

  static int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _toDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
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
