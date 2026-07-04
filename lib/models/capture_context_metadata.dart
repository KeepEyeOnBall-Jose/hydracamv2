import "json_value_parsers.dart";

class CameraPerspectiveMetadata {
  const CameraPerspectiveMetadata({
    required this.cameraPerspectiveId,
    required this.cameraPerspectiveLabel,
    this.cameraPerspectiveNotes,
  });

  final String cameraPerspectiveId;
  final String cameraPerspectiveLabel;
  final String? cameraPerspectiveNotes;

  static const CameraPerspectiveMetadata unknown = CameraPerspectiveMetadata(
    cameraPerspectiveId: "unknown",
    cameraPerspectiveLabel: "Unknown",
  );

  static const List<CameraPerspectiveMetadata> canonicalPerspectives = [
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "tin_back_floor_center",
      cameraPerspectiveLabel: "Tin to back, floor, centered",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "left_backglass_parallel",
      cameraPerspectiveLabel:
          "Left corner, behind glass, parallel to front wall",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "left_backglass_diagonal",
      cameraPerspectiveLabel:
          "Left corner, behind glass, diagonal to front-right",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "right_backglass_parallel",
      cameraPerspectiveLabel:
          "Right corner, behind glass, parallel to front wall",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "right_backglass_diagonal",
      cameraPerspectiveLabel:
          "Right corner, behind glass, diagonal to front-left",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "center_backglass_parallel",
      cameraPerspectiveLabel:
          "Centered behind back glass, parallel to front wall",
    ),
    CameraPerspectiveMetadata(
      cameraPerspectiveId: "center_backglass_overhead_parallel",
      cameraPerspectiveLabel:
          "Behind/above back glass, centered, parallel to front wall",
    ),
    unknown,
  ];

  static CameraPerspectiveMetadata fromId(String? id) {
    final normalized = id?.trim();
    if (normalized == null || normalized.isEmpty) {
      return unknown;
    }
    return canonicalPerspectives.firstWhere(
      (perspective) => perspective.cameraPerspectiveId == normalized,
      orElse: () => CameraPerspectiveMetadata(
        cameraPerspectiveId: normalized,
        cameraPerspectiveLabel: normalized,
      ),
    );
  }

  static CameraPerspectiveMetadata fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return unknown;
    }
    final id = json["cameraPerspectiveId"]?.toString();
    final known = fromId(id);
    final label = json["cameraPerspectiveLabel"]?.toString();
    final notes = json["cameraPerspectiveNotes"]?.toString();
    if (label == null || label.trim().isEmpty) {
      return CameraPerspectiveMetadata(
        cameraPerspectiveId: known.cameraPerspectiveId,
        cameraPerspectiveLabel: known.cameraPerspectiveLabel,
        cameraPerspectiveNotes:
            _nonEmpty(notes) ?? known.cameraPerspectiveNotes,
      );
    }
    return CameraPerspectiveMetadata(
      cameraPerspectiveId: known.cameraPerspectiveId,
      cameraPerspectiveLabel: label,
      cameraPerspectiveNotes: _nonEmpty(notes),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "cameraPerspectiveId": cameraPerspectiveId,
      "cameraPerspectiveLabel": cameraPerspectiveLabel,
      if (cameraPerspectiveNotes != null)
        "cameraPerspectiveNotes": cameraPerspectiveNotes,
    };
  }
}

class DeviceLevelMetadata {
  const DeviceLevelMetadata({
    required this.rollDegrees,
    required this.pitchDegrees,
    required this.toleranceDegrees,
    required this.isLevel,
    required this.sensorAvailable,
    required this.capturedAt,
  });

  final double? rollDegrees;
  final double? pitchDegrees;
  final double toleranceDegrees;
  final bool isLevel;
  final bool sensorAvailable;
  final DateTime capturedAt;

  static DeviceLevelMetadata unavailable({
    double toleranceDegrees = 5,
    DateTime? capturedAt,
  }) {
    return DeviceLevelMetadata(
      rollDegrees: null,
      pitchDegrees: null,
      toleranceDegrees: toleranceDegrees,
      isLevel: false,
      sensorAvailable: false,
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }

  static DeviceLevelMetadata fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return unavailable();
    }
    return DeviceLevelMetadata(
      rollDegrees: toDoubleOrNull(json["rollDegrees"]),
      pitchDegrees: toDoubleOrNull(json["pitchDegrees"]),
      toleranceDegrees: toDoubleOrNull(json["toleranceDegrees"]) ?? 5,
      isLevel: json["isLevel"] == true,
      sensorAvailable: json["sensorAvailable"] == true,
      capturedAt: optionalDateTime(json["capturedAt"]) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "rollDegrees": rollDegrees,
      "pitchDegrees": pitchDegrees,
      "toleranceDegrees": toleranceDegrees,
      "isLevel": isLevel,
      "sensorAvailable": sensorAvailable,
      "capturedAt": capturedAt.toIso8601String(),
    };
  }
}

class MediaCaptureContext {
  const MediaCaptureContext({
    required this.perspective,
    required this.level,
    required this.cameraName,
    required this.cameraLensDirection,
    required this.cameraSensorOrientation,
    required this.videoCaptureProfile,
    required this.deviceId,
  });

  final CameraPerspectiveMetadata perspective;
  final DeviceLevelMetadata level;
  final String? cameraName;
  final String? cameraLensDirection;
  final int? cameraSensorOrientation;
  final String? videoCaptureProfile;
  final String deviceId;

  static MediaCaptureContext? fromJson(Map<String, dynamic>? json) {
    if (json == null || !_hasContextKeys(json)) {
      return null;
    }
    final perspective = CameraPerspectiveMetadata.fromJson(json);
    return MediaCaptureContext(
      perspective: perspective,
      level: DeviceLevelMetadata.fromJson(toStringKeyedMap(json["deviceLevel"])),
      cameraName: _nonEmpty(json["cameraName"]?.toString()),
      cameraLensDirection: _nonEmpty(json["cameraLensDirection"]?.toString()),
      cameraSensorOrientation: toIntOrNull(json["cameraSensorOrientation"]),
      videoCaptureProfile: _nonEmpty(json["videoCaptureProfile"]?.toString()),
      deviceId: _nonEmpty(json["deviceId"]?.toString()) ?? "Unknown",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...perspective.toJson(),
      "deviceLevel": level.toJson(),
      "cameraName": cameraName,
      "cameraLensDirection": cameraLensDirection,
      "cameraSensorOrientation": cameraSensorOrientation,
      "videoCaptureProfile": videoCaptureProfile,
      "deviceId": deviceId,
    };
  }

  static bool _hasContextKeys(Map<String, dynamic> json) {
    return json.containsKey("cameraPerspectiveId") ||
        json.containsKey("cameraPerspectiveLabel") ||
        json.containsKey("deviceLevel") ||
        json.containsKey("cameraName") ||
        json.containsKey("videoCaptureProfile");
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
