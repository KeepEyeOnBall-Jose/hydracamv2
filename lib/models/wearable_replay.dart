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
      sessionGuid: _requiredString(json["sessionGuid"], "sessionGuid"),
      participantId: _requiredString(json["participantId"], "participantId"),
      sourceDeviceId: _requiredString(json["sourceDeviceId"], "sourceDeviceId"),
      pairedHydraCamDeviceId: _requiredString(
        json["pairedHydraCamDeviceId"],
        "pairedHydraCamDeviceId",
      ),
      localTimestamp: _requiredDateTime(
        json["localTimestamp"],
        "localTimestamp",
      ),
      sharedClockTimestamp: _requiredDateTime(
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
      trackId: _requiredString(json["trackId"], "trackId"),
      sessionGuid: _requiredString(json["sessionGuid"], "sessionGuid"),
      participantId: _requiredString(json["participantId"], "participantId"),
      sourceDeviceId: _requiredString(json["sourceDeviceId"], "sourceDeviceId"),
      pairedHydraCamDeviceId: _requiredString(
        json["pairedHydraCamDeviceId"],
        "pairedHydraCamDeviceId",
      ),
      sourceKind: _sourceKindFromName(json["sourceKind"]?.toString()),
      trackKind: _trackKindFromName(json["trackKind"]?.toString()),
      displayName: _requiredString(json["displayName"], "displayName"),
      startedAt: _requiredDateTime(json["startedAt"], "startedAt"),
      endedAt: _optionalDateTime(json["endedAt"]),
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
      sampleId: _requiredString(json["sampleId"], "sampleId"),
      trackId: _requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      heartRateBpm: _optionalInt(json["heartRateBpm"]),
      interBeatIntervalMs: _optionalInt(json["interBeatIntervalMs"]),
      accelerometerX: _optionalDouble(json["accelerometerX"]),
      accelerometerY: _optionalDouble(json["accelerometerY"]),
      accelerometerZ: _optionalDouble(json["accelerometerZ"]),
      gyroscopeX: _optionalDouble(json["gyroscopeX"]),
      gyroscopeY: _optionalDouble(json["gyroscopeY"]),
      gyroscopeZ: _optionalDouble(json["gyroscopeZ"]),
      motionIntensity: _optionalDouble(json["motionIntensity"]),
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
      markerId: _requiredString(json["markerId"], "markerId"),
      trackId: _requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      markerType: _requiredString(json["markerType"], "markerType"),
      label: _requiredString(json["label"], "label"),
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
      recordingId: _requiredString(json["recordingId"], "recordingId"),
      trackId: _requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      mediaPath: _requiredString(json["mediaPath"], "mediaPath"),
      captureMode: _povCaptureModeFromName(json["captureMode"]?.toString()),
      startedAt: _requiredDateTime(json["startedAt"], "startedAt"),
      endedAt: _requiredDateTime(json["endedAt"], "endedAt"),
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
      feedbackId: _requiredString(json["feedbackId"], "feedbackId"),
      trackId: _requiredString(json["trackId"], "trackId"),
      context: WearableRecordContext.fromJson(json),
      channel: _feedbackChannelFromName(json["channel"]?.toString()),
      trigger: _requiredString(json["trigger"], "trigger"),
      message: _requiredString(json["message"], "message"),
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
      calibrationId: _requiredString(json["calibrationId"], "calibrationId"),
      context: WearableRecordContext.fromJson(json),
      ritual: _requiredString(json["ritual"], "ritual"),
      observedSourceDeviceIds: _stringList(json["observedSourceDeviceIds"]),
      targetAlignmentMs: _optionalInt(json["targetAlignmentMs"]) ?? 50,
      measuredAlignmentErrorMs:
          _optionalInt(json["measuredAlignmentErrorMs"]) ?? 0,
      performedAt: _requiredDateTime(json["performedAt"], "performedAt"),
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

String _requiredString(Object? value, String field) {
  final stringValue = value?.toString().trim();
  if (stringValue == null || stringValue.isEmpty) {
    throw FormatException("missing required field $field");
  }
  return stringValue;
}

DateTime _requiredDateTime(Object? value, String field) {
  final parsed = _optionalDateTime(value);
  if (parsed == null) {
    throw FormatException("missing required field $field");
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

bool _boolValue(Object? value, {required bool defaultValue}) {
  return value is bool ? value : defaultValue;
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _optionalDouble(Object? value) {
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
