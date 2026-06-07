import "package:flutter/services.dart";

class CameraHardwareMetadata {
  const CameraHardwareMetadata({
    required this.cameraId,
    required this.focalLengths,
    this.maxDigitalZoom,
  });

  final String cameraId;
  final List<double> focalLengths;
  final double? maxDigitalZoom;

  String? get detailText {
    final parts = <String>[];
    if (focalLengths.isNotEmpty) {
      parts.add(
        focalLengths
            .map((length) => "${length.toStringAsFixed(1)}mm")
            .join(", "),
      );
    }
    final zoom = maxDigitalZoom;
    if (zoom != null && zoom > 0) {
      parts.add("max zoom ${zoom.toStringAsFixed(1)}x");
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(" • ");
  }

  static CameraHardwareMetadata? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return null;
    }
    final cameraId = map["cameraId"]?.toString();
    if (cameraId == null || cameraId.isEmpty) {
      return null;
    }
    return CameraHardwareMetadata(
      cameraId: cameraId,
      focalLengths: _toDoubleList(map["focalLengths"]),
      maxDigitalZoom: _toDouble(map["maxDigitalZoom"]),
    );
  }

  static List<double> _toDoubleList(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .map(_toDouble)
        .whereType<double>()
        .where((length) => length > 0)
        .toList(growable: false);
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

class CameraHardwareMetadataService {
  CameraHardwareMetadataService._();

  static const MethodChannel _channel =
      MethodChannel("hydracamv2/camera_metadata");

  static Future<CameraHardwareMetadata?> getCameraMetadata(
      String cameraId) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        "getCameraMetadata",
        {"cameraId": cameraId},
      );
      return CameraHardwareMetadata.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
