import "json_value_parsers.dart";
import "sync_metadata.dart";

enum WearableSourceKind { galaxyWatch, rayBanMeta, phone, unknown }

enum WearableTrackKind { telemetry, pov, feedback }

enum PovCaptureMode { continuous, rollingHighlight, manual }

enum FeedbackChannel { watchHaptic, glassesAudio, phoneUi }

class WearableRecordContext {
  const WearableRecordContext({
    required this.sessionGuid,
    required this.participantId,
    required this.sourceDeviceId,
    required this.pairedHydraCamDeviceId,
    required this.localTimestamp,
    required this.sharedClockTimestamp,
    required this.syncMetadata,
    this.publishConsent = true,
    this.shareReady = true,
  });

  final String sessionGuid;
  final String participantId;
  final String sourceDeviceId;
  final String pairedHydraCamDeviceId;
  final DateTime localTimestamp;
  final DateTime sharedClockTimestamp;
  final SyncMetadata syncMetadata;
  final bool publishConsent;
  final bool shareReady;

  factory WearableRecordContext.fromLocalTimestamp({
    required String sessionGuid,
    required String participantId,
    required String sourceDeviceId,
    required String pairedHydraCamDeviceId,
    required DateTime localTimestamp,
    required SyncMetadata syncMetadata,
    bool publishConsent = true,
    bool shareReady = true,
  }) {
    return WearableRecordContext(
      sessionGuid: sessionGuid,
      participantId: participantId,
      sourceDeviceId: sourceDeviceId,
      pairedHydraCamDeviceId: pairedHydraCamDeviceId,
      localTimestamp: localTimestamp,
      sharedClockTimestamp: sharedClockTimestampFor(
        localTimestamp,
        syncMetadata,
      ),
      syncMetadata: syncMetadata,
      publishConsent: publishConsent,
      shareReady: shareReady,
    );
  }

  static DateTime sharedClockTimestampFor(
    DateTime localTimestamp,
    SyncMetadata syncMetadata,
  ) {
    return localTimestamp.add(Duration(milliseconds: syncMetadata.offsetMs));
  }

  Map<String, dynamic> toJson() {
    return {
      "sessionGuid": sessionGuid,
      "participantId": participantId,
      "sourceDeviceId": sourceDeviceId,
      "pairedHydraCamDeviceId": pairedHydraCamDeviceId,
      "localTimestamp": localTimestamp.toIso8601String(),
      "sharedClockTimestamp": sharedClockTimestamp.toIso8601String(),
      "syncMetadata": syncMetadata.toJson(),
      "publishConsent": publishConsent,
      "shareReady": shareReady,
      "syncConfidence": syncMetadata.confidence.name,
    };
  }

  static WearableRecordContext fromJson(Object? value) {
    final json = _asMap(value);
    final syncMetadata = SyncMetadata.fromJson(json["syncMetadata"]);
    if (syncMetadata == null) {
      throw const FormatException("wearable context missing syncMetadata");
    }
    return WearableRecordContext(
      sessionGuid: requiredString(json["sessionGuid"], "sessionGuid"),
      participantId: requiredString(json["participantId"], "participantId"),
      sourceDeviceId: requiredString(json["sourceDeviceId"], "sourceDeviceId"),
      pairedHydraCamDeviceId: requiredString(
        json["pairedHydraCamDeviceId"],
        "pairedHydraCamDeviceId",
      ),
      localTimestamp: requiredDateTime(
        json["localTimestamp"],
        "localTimestamp",
      ),
      sharedClockTimestamp: requiredDateTime(
        json["sharedClockTimestamp"],
        "sharedClockTimestamp",
      ),
      syncMetadata: syncMetadata,
      publishConsent: _boolValue(json["publishConsent"], defaultValue: true),
      shareReady: _boolValue(json["shareReady"], defaultValue: true),
    );
  }
}

class WearableTrack {
  const WearableTrack({
    required this.trackId,
    required this.sessionGuid,
    required this.participantId,
    required this.sourceDeviceId,
    required this.pairedHydraCamDeviceId,
    required this.sourceKind,
    required this.trackKind,
    required this.displayName,
    required this.startedAt,
    required this.syncMetadata,
    this.endedAt,
    this.publishConsent = true,
    this.shareReady = true,
    this.metadata = const {},
  });

  final String trackId;
  final String sessionGuid;
  final String participantId;
  final String sourceDeviceId;
  final String pairedHydraCamDeviceId;
  final WearableSourceKind sourceKind;
  final WearableTrackKind trackKind;
  final String displayName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SyncMetadata syncMetadata;
  final bool publishConsent;
  final bool shareReady;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() {
    return {
      "trackId": trackId,
      "sessionGuid": sessionGuid,
      "participantId": participantId,
      "sourceDeviceId": sourceDeviceId,
      "pairedHydraCamDeviceId": pairedHydraCamDeviceId,
      "sourceKind": sourceKind.name,
      "trackKind": trackKind.name,
      "displayName": displayName,
      "startedAt": startedAt.toIso8601String(),
      if (endedAt != null) "endedAt": endedAt!.toIso8601String(),
      "syncMetadata": syncMetadata.toJson(),
      "publishConsent": publishConsent,
      "shareReady": shareReady,
      "syncConfidence": syncMetadata.confidence.name,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static WearableTrack fromJson(Object? value) {
    final json = _asMap(value);
    final syncMetadata = SyncMetadata.fromJson(json["syncMetadata"]);
    if (syncMetadata == null) {
      throw const FormatException("wearable track missing syncMetadata");
    }
    return WearableTrack(
      trackId: requiredString(json["trackId"], "trackId"),
      sessionGuid: requiredString(json["sessionGuid"], "sessionGuid"),
      participantId: requiredString(json["participantId"], "participantId"),
      sourceDeviceId: requiredString(json["sourceDeviceId"], "sourceDeviceId"),
      pairedHydraCamDeviceId: requiredString(
        json["pairedHydraCamDeviceId"],
        "pairedHydraCamDeviceId",
      ),
      sourceKind: _sourceKindFromName(json["sourceKind"]?.toString()),
      trackKind: _trackKindFromName(json["trackKind"]?.toString()),
      displayName: requiredString(json["displayName"], "displayName"),
      startedAt: requiredDateTime(json["startedAt"], "startedAt"),
      endedAt: optionalDateTime(json["endedAt"]),
      syncMetadata: syncMetadata,
      publishConsent: _boolValue(json["publishConsent"], defaultValue: true),
      shareReady: _boolValue(json["shareReady"], defaultValue: true),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class WearableSample {
  const WearableSample({
    required this.sampleId,
    required this.trackId,
    required this.context,
    this.heartRateBpm,
    this.interBeatIntervalMs,
    this.accelerometerX,
    this.accelerometerY,
    this.accelerometerZ,
    this.gyroscopeX,
    this.gyroscopeY,
    this.gyroscopeZ,
    this.motionIntensity,
    this.metadata = const {},
  });

  final String sampleId;
  final String trackId;
  final WearableRecordContext context;
  final int? heartRateBpm;
  final int? interBeatIntervalMs;
  final double? accelerometerX;
  final double? accelerometerY;
  final double? accelerometerZ;
  final double? gyroscopeX;
  final double? gyroscopeY;
  final double? gyroscopeZ;
  final double? motionIntensity;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() {
    return {
      ...context.toJson(),
      "recordType": "wearableSample",
      "sampleId": sampleId,
      "trackId": trackId,
      if (heartRateBpm != null) "heartRateBpm": heartRateBpm,
      if (interBeatIntervalMs != null)
        "interBeatIntervalMs": interBeatIntervalMs,
      if (accelerometerX != null) "accelerometerX": accelerometerX,
      if (accelerometerY != null) "accelerometerY": accelerometerY,
      if (accelerometerZ != null) "accelerometerZ": accelerometerZ,
      if (gyroscopeX != null) "gyroscopeX": gyroscopeX,
      if (gyroscopeY != null) "gyroscopeY": gyroscopeY,
      if (gyroscopeZ != null) "gyroscopeZ": gyroscopeZ,
      if (motionIntensity != null) "motionIntensity": motionIntensity,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static WearableSample fromJson(Object? value) {
    final json = _asMap(value);
    return WearableSample(
      sampleId: requiredString(json["sampleId"], "sampleId"),
      trackId: requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      heartRateBpm: roundedIntOrNull(json["heartRateBpm"]),
      interBeatIntervalMs: roundedIntOrNull(json["interBeatIntervalMs"]),
      accelerometerX: toDoubleOrNull(json["accelerometerX"]),
      accelerometerY: toDoubleOrNull(json["accelerometerY"]),
      accelerometerZ: toDoubleOrNull(json["accelerometerZ"]),
      gyroscopeX: toDoubleOrNull(json["gyroscopeX"]),
      gyroscopeY: toDoubleOrNull(json["gyroscopeY"]),
      gyroscopeZ: toDoubleOrNull(json["gyroscopeZ"]),
      motionIntensity: toDoubleOrNull(json["motionIntensity"]),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class WearableMarker {
  const WearableMarker({
    required this.markerId,
    required this.trackId,
    required this.context,
    required this.markerType,
    required this.label,
    this.metadata = const {},
  });

  final String markerId;
  final String trackId;
  final WearableRecordContext context;
  final String markerType;
  final String label;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() {
    return {
      ...context.toJson(),
      "recordType": "wearableMarker",
      "markerId": markerId,
      "trackId": trackId,
      "markerType": markerType,
      "label": label,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static WearableMarker fromJson(Object? value) {
    final json = _asMap(value);
    return WearableMarker(
      markerId: requiredString(json["markerId"], "markerId"),
      trackId: requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      markerType: requiredString(json["markerType"], "markerType"),
      label: requiredString(json["label"], "label"),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class PovRecording {
  const PovRecording({
    required this.recordingId,
    required this.trackId,
    required this.context,
    required this.mediaPath,
    required this.captureMode,
    required this.startedAt,
    required this.endedAt,
    required this.hasAudio,
    this.audioPublishDefault = true,
    this.reviewRequired = true,
    this.metadata = const {},
  });

  final String recordingId;
  final String trackId;
  final WearableRecordContext context;
  final String mediaPath;
  final PovCaptureMode captureMode;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool hasAudio;
  final bool audioPublishDefault;
  final bool reviewRequired;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() {
    return {
      ...context.toJson(),
      "recordType": "povRecording",
      "recordingId": recordingId,
      "trackId": trackId,
      "mediaPath": mediaPath,
      "captureMode": captureMode.name,
      "startedAt": startedAt.toIso8601String(),
      "endedAt": endedAt.toIso8601String(),
      "hasAudio": hasAudio,
      "audioPublishDefault": audioPublishDefault,
      "reviewRequired": reviewRequired,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static PovRecording fromJson(Object? value) {
    final json = _asMap(value);
    return PovRecording(
      recordingId: requiredString(json["recordingId"], "recordingId"),
      trackId: requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      mediaPath: requiredString(json["mediaPath"], "mediaPath"),
      captureMode: _povCaptureModeFromName(json["captureMode"]?.toString()),
      startedAt: requiredDateTime(json["startedAt"], "startedAt"),
      endedAt: requiredDateTime(json["endedAt"], "endedAt"),
      hasAudio: _boolValue(json["hasAudio"], defaultValue: false),
      audioPublishDefault:
          _boolValue(json["audioPublishDefault"], defaultValue: true),
      reviewRequired: _boolValue(json["reviewRequired"], defaultValue: true),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class FeedbackEvent {
  const FeedbackEvent({
    required this.feedbackId,
    required this.trackId,
    required this.context,
    required this.channel,
    required this.trigger,
    required this.message,
    this.metadata = const {},
  });

  final String feedbackId;
  final String trackId;
  final WearableRecordContext context;
  final FeedbackChannel channel;
  final String trigger;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() {
    return {
      ...context.toJson(),
      "recordType": "feedbackEvent",
      "feedbackId": feedbackId,
      "trackId": trackId,
      "channel": channel.name,
      "trigger": trigger,
      "message": message,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static FeedbackEvent fromJson(Object? value) {
    final json = _asMap(value);
    return FeedbackEvent(
      feedbackId: requiredString(json["feedbackId"], "feedbackId"),
      trackId: requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      channel: _feedbackChannelFromName(json["channel"]?.toString()),
      trigger: requiredString(json["trigger"], "trigger"),
      message: requiredString(json["message"], "message"),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class WearableSyncCalibration {
  const WearableSyncCalibration({
    required this.calibrationId,
    required this.context,
    required this.ritual,
    required this.observedSourceDeviceIds,
    required this.targetAlignmentMs,
    required this.measuredAlignmentErrorMs,
    required this.performedAt,
    this.metadata = const {},
  });

  final String calibrationId;
  final WearableRecordContext context;
  final String ritual;
  final List<String> observedSourceDeviceIds;
  final int targetAlignmentMs;
  final int measuredAlignmentErrorMs;
  final DateTime performedAt;
  final Map<String, Object?> metadata;

  bool get withinTarget => measuredAlignmentErrorMs <= targetAlignmentMs;

  Map<String, dynamic> toJson() {
    return {
      ...context.toJson(),
      "recordType": "wearableSyncCalibration",
      "calibrationId": calibrationId,
      "ritual": ritual,
      "observedSourceDeviceIds": observedSourceDeviceIds,
      "targetAlignmentMs": targetAlignmentMs,
      "measuredAlignmentErrorMs": measuredAlignmentErrorMs,
      "performedAt": performedAt.toIso8601String(),
      "withinTarget": withinTarget,
      if (metadata.isNotEmpty) "metadata": metadata,
    };
  }

  static WearableSyncCalibration fromJson(Object? value) {
    final json = _asMap(value);
    return WearableSyncCalibration(
      calibrationId: requiredString(json["calibrationId"], "calibrationId"),
      context: WearableRecordContext.fromJson(json),
      ritual: requiredString(json["ritual"], "ritual"),
      observedSourceDeviceIds: _stringList(json["observedSourceDeviceIds"]),
      targetAlignmentMs: roundedIntOrNull(json["targetAlignmentMs"]) ?? 50,
      measuredAlignmentErrorMs:
          roundedIntOrNull(json["measuredAlignmentErrorMs"]) ?? 0,
      performedAt: requiredDateTime(json["performedAt"], "performedAt"),
      metadata: _objectMap(json["metadata"]),
    );
  }
}

class WearableReplayUploadManifest {
  const WearableReplayUploadManifest({
    required this.sessionGuid,
    required this.generatedAt,
    required this.trackFiles,
    required this.sampleFiles,
    required this.calibrationFiles,
    required this.markerFiles,
    required this.povRecordingFiles,
    required this.povMediaFiles,
    required this.feedbackFiles,
  });

  final String sessionGuid;
  final DateTime generatedAt;
  final List<String> trackFiles;
  final List<String> sampleFiles;
  final List<String> calibrationFiles;
  final List<String> markerFiles;
  final List<String> povRecordingFiles;
  final List<String> povMediaFiles;
  final List<String> feedbackFiles;

  Map<String, dynamic> toJson() {
    return {
      "manifestVersion": 1,
      "sessionGuid": sessionGuid,
      "generatedAt": generatedAt.toIso8601String(),
      "trackFiles": trackFiles,
      "sampleFiles": sampleFiles,
      "calibrationFiles": calibrationFiles,
      "markerFiles": markerFiles,
      "povRecordingFiles": povRecordingFiles,
      "povMediaFiles": povMediaFiles,
      "feedbackFiles": feedbackFiles,
      "mediaTimelineIntent": {
        "registerPovAsReplayAngle": true,
        "renderAudioOnByDefault": true,
        "renderHeartRateOverlay": true,
        "renderMotionOverlay": true,
        "requirePrePublishReview": true,
      },
    };
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException("expected JSON object");
}

Map<String, Object?> _objectMap(Object? value) {
  if (value == null) {
    return const {};
  }
  return _asMap(value).cast<String, Object?>();
}

bool _boolValue(Object? value, {required bool defaultValue}) {
  return value is bool ? value : defaultValue;
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value
      .map((item) => item?.toString().trim() ?? "")
      .where((item) => item.isNotEmpty)
      .toList();
}

WearableSourceKind _sourceKindFromName(String? name) {
  return WearableSourceKind.values.firstWhere(
    (value) => value.name == name,
    orElse: () => WearableSourceKind.unknown,
  );
}

WearableTrackKind _trackKindFromName(String? name) {
  return WearableTrackKind.values.firstWhere(
    (value) => value.name == name,
    orElse: () => WearableTrackKind.telemetry,
  );
}

PovCaptureMode _povCaptureModeFromName(String? name) {
  return PovCaptureMode.values.firstWhere(
    (value) => value.name == name,
    orElse: () => PovCaptureMode.rollingHighlight,
  );
}

FeedbackChannel _feedbackChannelFromName(String? name) {
  return FeedbackChannel.values.firstWhere(
    (value) => value.name == name,
    orElse: () => FeedbackChannel.phoneUi,
  );
}
