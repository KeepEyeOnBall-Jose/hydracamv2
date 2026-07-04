import "package:flutter/services.dart";

import "../models/json_value_parsers.dart";
import "../models/wearable_replay.dart";

class WearableReplayBridgeCapabilities {
  const WearableReplayBridgeCapabilities({
    required this.platform,
    required this.channelAvailable,
    required this.metaDatAvailable,
    required this.metaMockAvailable,
    required this.watchCompanionAvailable,
    required this.watchMockAvailable,
    required this.supportsWatchHaptics,
    required this.supportsGlassesAudio,
    required this.supportsRollingPovFallback,
    required this.requiresPhysicalMetaHardware,
    required this.requiresPhysicalWatchHardware,
    this.reason,
  });

  final String platform;
  final bool channelAvailable;
  final bool metaDatAvailable;
  final bool metaMockAvailable;
  final bool watchCompanionAvailable;
  final bool watchMockAvailable;
  final bool supportsWatchHaptics;
  final bool supportsGlassesAudio;
  final bool supportsRollingPovFallback;
  final bool requiresPhysicalMetaHardware;
  final bool requiresPhysicalWatchHardware;
  final String? reason;

  bool get canSimulateWearableReplay {
    return channelAvailable && metaMockAvailable && watchMockAvailable;
  }

  factory WearableReplayBridgeCapabilities.fromMap(
    Map<dynamic, dynamic>? map,
  ) {
    if (map == null) {
      return const WearableReplayBridgeCapabilities.unsupported(
        reason: "Wearable replay native capabilities were empty.",
      );
    }
    return WearableReplayBridgeCapabilities(
      platform: stringOrFallback(map["platform"], fallback: "unknown"),
      channelAvailable: boolOrFallback(map["channelAvailable"]),
      metaDatAvailable: boolOrFallback(map["metaDatAvailable"]),
      metaMockAvailable: boolOrFallback(map["metaMockAvailable"]),
      watchCompanionAvailable: boolOrFallback(map["watchCompanionAvailable"]),
      watchMockAvailable: boolOrFallback(map["watchMockAvailable"]),
      supportsWatchHaptics: boolOrFallback(map["supportsWatchHaptics"]),
      supportsGlassesAudio: boolOrFallback(map["supportsGlassesAudio"]),
      supportsRollingPovFallback: boolOrFallback(
        map["supportsRollingPovFallback"],
        fallback: boolOrFallback(map["metaMockAvailable"]),
      ),
      requiresPhysicalMetaHardware: boolOrFallback(
        map["requiresPhysicalMetaHardware"],
        fallback: true,
      ),
      requiresPhysicalWatchHardware: boolOrFallback(
        map["requiresPhysicalWatchHardware"],
        fallback: true,
      ),
      reason: map["reason"] is String ? map["reason"] as String : null,
    );
  }

  const factory WearableReplayBridgeCapabilities.unsupported({
    String platform,
    String? reason,
  }) = _UnsupportedWearableReplayBridgeCapabilities;
}

class _UnsupportedWearableReplayBridgeCapabilities
    extends WearableReplayBridgeCapabilities {
  const _UnsupportedWearableReplayBridgeCapabilities({
    super.platform = "unknown",
    super.reason,
  }) : super(
          channelAvailable: false,
          metaDatAvailable: false,
          metaMockAvailable: false,
          watchCompanionAvailable: false,
          watchMockAvailable: false,
          supportsWatchHaptics: false,
          supportsGlassesAudio: false,
          supportsRollingPovFallback: false,
          requiresPhysicalMetaHardware: true,
          requiresPhysicalWatchHardware: true,
        );
}

class MetaPovCaptureRequest {
  const MetaPovCaptureRequest({
    required this.sessionGuid,
    required this.participantId,
    required this.sourceDeviceId,
    required this.pairedHydraCamDeviceId,
    required this.recordingId,
    this.captureMode = PovCaptureMode.continuous,
    this.includeAudio = true,
    this.targetDurationSeconds = 30,
  });

  final String sessionGuid;
  final String participantId;
  final String sourceDeviceId;
  final String pairedHydraCamDeviceId;
  final String recordingId;
  final PovCaptureMode captureMode;
  final bool includeAudio;
  final int targetDurationSeconds;

  Map<String, Object?> toMap() {
    return {
      "sessionGuid": sessionGuid,
      "participantId": participantId,
      "sourceDeviceId": sourceDeviceId,
      "pairedHydraCamDeviceId": pairedHydraCamDeviceId,
      "recordingId": recordingId,
      "captureMode": captureMode.name,
      "includeAudio": includeAudio,
      "targetDurationSeconds": targetDurationSeconds,
    };
  }
}

class MetaPovCaptureResult {
  const MetaPovCaptureResult({
    required this.recordingId,
    required this.mediaPath,
    required this.startedAt,
    required this.endedAt,
    required this.captureMode,
    required this.hasAudio,
    required this.mockCapture,
  });

  final String recordingId;
  final String mediaPath;
  final DateTime startedAt;
  final DateTime endedAt;
  final PovCaptureMode captureMode;
  final bool hasAudio;
  final bool mockCapture;

  factory MetaPovCaptureResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      throw const FormatException("Meta POV capture result was empty.");
    }
    return MetaPovCaptureResult(
      recordingId: requiredString(map["recordingId"], "recordingId"),
      mediaPath: requiredString(map["mediaPath"], "mediaPath"),
      startedAt: requiredDateTime(map["startedAt"], "startedAt"),
      endedAt: requiredDateTime(map["endedAt"], "endedAt"),
      captureMode: _povCaptureModeFromName(map["captureMode"]?.toString()),
      hasAudio: boolOrFallback(map["hasAudio"]),
      mockCapture: boolOrFallback(map["mockCapture"]),
    );
  }
}

class WatchTelemetryReading {
  const WatchTelemetryReading({
    required this.sourceDeviceId,
    required this.localTimestamp,
    this.heartRateBpm,
    this.interBeatIntervalMs,
    this.accelerometerX,
    this.accelerometerY,
    this.accelerometerZ,
    this.gyroscopeX,
    this.gyroscopeY,
    this.gyroscopeZ,
    this.motionIntensity,
    this.mockReading = false,
  });

  final String sourceDeviceId;
  final DateTime localTimestamp;
  final int? heartRateBpm;
  final int? interBeatIntervalMs;
  final double? accelerometerX;
  final double? accelerometerY;
  final double? accelerometerZ;
  final double? gyroscopeX;
  final double? gyroscopeY;
  final double? gyroscopeZ;
  final double? motionIntensity;
  final bool mockReading;

  factory WatchTelemetryReading.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      throw const FormatException("Watch telemetry reading was empty.");
    }
    return WatchTelemetryReading(
      sourceDeviceId: requiredString(map["sourceDeviceId"], "sourceDeviceId"),
      localTimestamp: requiredDateTime(
        map["localTimestamp"],
        "localTimestamp",
      ),
      heartRateBpm: roundedIntOrNull(map["heartRateBpm"]),
      interBeatIntervalMs: roundedIntOrNull(map["interBeatIntervalMs"]),
      accelerometerX: toDoubleOrNull(map["accelerometerX"]),
      accelerometerY: toDoubleOrNull(map["accelerometerY"]),
      accelerometerZ: toDoubleOrNull(map["accelerometerZ"]),
      gyroscopeX: toDoubleOrNull(map["gyroscopeX"]),
      gyroscopeY: toDoubleOrNull(map["gyroscopeY"]),
      gyroscopeZ: toDoubleOrNull(map["gyroscopeZ"]),
      motionIntensity: toDoubleOrNull(map["motionIntensity"]),
      mockReading: boolOrFallback(map["mockReading"]),
    );
  }
}

class WearableReplayBridgeService {
  WearableReplayBridgeService({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const channelName = "hydracamv2/wearable_replay";

  final MethodChannel _channel;

  Future<WearableReplayBridgeCapabilities> getCapabilities() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        "getCapabilities",
      );
      return WearableReplayBridgeCapabilities.fromMap(result);
    } on MissingPluginException catch (error) {
      return WearableReplayBridgeCapabilities.unsupported(
        reason: "Wearable replay native channel is not available: $error",
      );
    }
  }

  Future<MetaPovCaptureResult> startMetaPovCapture(
    MetaPovCaptureRequest request,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      "startMetaPovCapture",
      request.toMap(),
    );
    return MetaPovCaptureResult.fromMap(result);
  }

  Future<MetaPovCaptureResult> stopMetaPovCapture(String recordingId) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      "stopMetaPovCapture",
      {"recordingId": recordingId},
    );
    return MetaPovCaptureResult.fromMap(result);
  }

  Future<WatchTelemetryReading> pollWatchTelemetry({
    required String sourceDeviceId,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      "pollWatchTelemetry",
      {"sourceDeviceId": sourceDeviceId},
    );
    return WatchTelemetryReading.fromMap(result);
  }

  Future<bool> sendFeedback(FeedbackEvent event) async {
    final result = await _channel.invokeMethod<bool>(
      "sendFeedback",
      event.toJson(),
    );
    return result == true;
  }
}

PovCaptureMode _povCaptureModeFromName(String? name) {
  return PovCaptureMode.values.firstWhere(
    (value) => value.name == name,
    orElse: () => PovCaptureMode.rollingHighlight,
  );
}
