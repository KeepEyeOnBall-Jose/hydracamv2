// GENERATED FILE - DO NOT EDIT BY HAND.
// Source: packages/court-contracts (CONTRACT_VERSION = "1.29")
// Generator: packages/court-contracts/scripts/generate-mobile-c1.ts

const int c1ProtocolVersion = 1;
const String c1ContractVersion = "1.29";
const String c1ContractVersionPattern = r"^\d+(?:\.\d+)+$";
const int c1StreamIdMaxBytes = 512;
const String c1StreamIdPattern =
    r"^publish:court/([A-Za-z0-9_-]{1,64})/([A-Za-z0-9_-]{1,64}):device:([A-"
    r"Za-z0-9_-]{22,128})$";
const String c1PublishTokenPattern = r"^[A-Za-z0-9_-]{22,128}$";
const String c1Sha256Pattern = r"^[0-9a-f]{64}$";

// Message types: Bidirectional
const String c1MsgAck = "ack";
const String c1MsgNack = "nack";

// Message types: Device -> Cloud
const String c1MsgHello = "hello";
const String c1MsgState = "state";
const String c1MsgClockPing = "clock.ping";
const String c1MsgRecordingStarted = "recording.started";
const String c1MsgRecordingSegment = "recording.segment";
const String c1MsgRecordingStopped = "recording.stopped";
const String c1MsgRecordingGap = "recording.gap";
const String c1MsgGestureDetected = "gesture.detected";

// Message types: Cloud -> Device
const String c1MsgClockPong = "clock.pong";
const String c1MsgPreviewStart = "preview.start";
const String c1MsgPreviewStop = "preview.stop";
const String c1MsgRecordPrepare = "record.prepare";
const String c1MsgRecordStart = "record.start";
const String c1MsgRecordStop = "record.stop";
const String c1MsgSignalEmit = "signal.emit";
const String c1MsgSnapshot = "snapshot";
const String c1MsgUploadPolicy = "upload.policy";
const String c1MsgMastersUpload = "masters.upload";
const String c1MsgConfigSet = "config.set";
const String c1MsgAppUpdate = "app.update";
const String c1MsgLogsUpload = "logs.upload";

const List<String> c1BidirectionalMessageTypes = <String>[c1MsgAck, c1MsgNack];
const List<String> c1DeviceMessageTypes = <String>[
  c1MsgAck,
  c1MsgNack,
  c1MsgHello,
  c1MsgState,
  c1MsgClockPing,
  c1MsgRecordingStarted,
  c1MsgRecordingSegment,
  c1MsgRecordingStopped,
  c1MsgRecordingGap,
  c1MsgGestureDetected,
];
const List<String> c1CloudMessageTypes = <String>[
  c1MsgAck,
  c1MsgNack,
  c1MsgClockPong,
  c1MsgPreviewStart,
  c1MsgPreviewStop,
  c1MsgRecordPrepare,
  c1MsgRecordStart,
  c1MsgRecordStop,
  c1MsgSignalEmit,
  c1MsgSnapshot,
  c1MsgUploadPolicy,
  c1MsgMastersUpload,
  c1MsgConfigSet,
  c1MsgAppUpdate,
  c1MsgLogsUpload,
];
const List<String> c1AllMessageTypes = <String>[
  c1MsgAck,
  c1MsgNack,
  c1MsgHello,
  c1MsgState,
  c1MsgClockPing,
  c1MsgRecordingStarted,
  c1MsgRecordingSegment,
  c1MsgRecordingStopped,
  c1MsgRecordingGap,
  c1MsgGestureDetected,
  c1MsgClockPong,
  c1MsgPreviewStart,
  c1MsgPreviewStop,
  c1MsgRecordPrepare,
  c1MsgRecordStart,
  c1MsgRecordStop,
  c1MsgSignalEmit,
  c1MsgSnapshot,
  c1MsgUploadPolicy,
  c1MsgMastersUpload,
  c1MsgConfigSet,
  c1MsgAppUpdate,
  c1MsgLogsUpload,
];

// Nack codes
const String c1NackNotRooted = "not_rooted";
const String c1NackBusy = "busy";
const String c1NackBadRequest = "bad_request";
const String c1NackUnsupported = "unsupported";
const String c1NackNotEnrolled = "not_enrolled";
const String c1NackInternal = "internal";
const String c1NackTimeout = "timeout";
const String c1NackGone = "gone";
const String c1NackNotPrepared = "not_prepared";
const String c1NackBadRange = "bad_range";
const String c1NackStorageFull = "storage_full";
const List<String> c1NackCodes = <String>[
  c1NackNotRooted,
  c1NackBusy,
  c1NackBadRequest,
  c1NackUnsupported,
  c1NackNotEnrolled,
  c1NackInternal,
  c1NackTimeout,
  c1NackGone,
  c1NackNotPrepared,
  c1NackBadRange,
  c1NackStorageFull,
];

// Device modes
const String c1DeviceModeIdle = "idle";
const String c1DeviceModePreviewing = "previewing";
const String c1DeviceModeArmed = "armed";
const String c1DeviceModeRecording = "recording";
const String c1DeviceModeUploading = "uploading";
const String c1DeviceModeUpdating = "updating";
const String c1DeviceModeDegraded = "degraded";
const String c1DeviceModeError = "error";
const List<String> c1DeviceModes = <String>[
  c1DeviceModeIdle,
  c1DeviceModePreviewing,
  c1DeviceModeArmed,
  c1DeviceModeRecording,
  c1DeviceModeUploading,
  c1DeviceModeUpdating,
  c1DeviceModeDegraded,
  c1DeviceModeError,
];

enum C1DeviceMode {
  idle(c1DeviceModeIdle),
  previewing(c1DeviceModePreviewing),
  armed(c1DeviceModeArmed),
  recording(c1DeviceModeRecording),
  uploading(c1DeviceModeUploading),
  updating(c1DeviceModeUpdating),
  degraded(c1DeviceModeDegraded),
  error(c1DeviceModeError);

  const C1DeviceMode(this.wire);
  final String wire;
}

// Blocked reasons
const String c1BlockedStorageFull = "storage_full";
const List<String> c1BlockedReasons = <String>[c1BlockedStorageFull];

// Recording tiers
const String c1TierProxy = "proxy";
const String c1TierMaster = "master";
const List<String> c1Tiers = <String>[c1TierProxy, c1TierMaster];

// Recording gap reasons
const String c1GapReasonNoCompleteFrame = "no-complete-frame";
const List<String> c1GapReasons = <String>[c1GapReasonNoCompleteFrame];

// Upload policy master modes
const String c1MasterModeNever = "never";
const String c1MasterModeOnRequest = "on-request";
const String c1MasterModeWindow = "window";
const String c1MasterModeStream = "stream";
const List<String> c1MasterModes = <String>[
  c1MasterModeNever,
  c1MasterModeOnRequest,
  c1MasterModeWindow,
  c1MasterModeStream,
];

// Capture lenses
const String c1LensWide = "wide";
const String c1LensUltrawide = "ultrawide";
const String c1LensTele = "tele";
const List<String> c1Lenses = <String>[c1LensWide, c1LensUltrawide, c1LensTele];

// Video codecs
const String c1VideoCodecAvc = "avc";
const String c1VideoCodecHevc = "hevc";
const List<String> c1VideoCodecs = <String>[c1VideoCodecAvc, c1VideoCodecHevc];

// Rotation degrees
const int c1RotationDeg0 = 0;
const int c1RotationDeg90 = 90;
const int c1RotationDeg180 = 180;
const int c1RotationDeg270 = 270;
const List<int> c1RotationDegrees = <int>[
  c1RotationDeg0,
  c1RotationDeg90,
  c1RotationDeg180,
  c1RotationDeg270,
];

// Profile constants
const String c1ProfileMasterRes2160p = "2160p";
const String c1ProfileMasterRes1080p = "1080p";
const String c1ProfileMasterRes720p = "720p";
const List<String> c1ProfileMasterResolutions = <String>[
  c1ProfileMasterRes2160p,
  c1ProfileMasterRes1080p,
  c1ProfileMasterRes720p,
];
const int c1ProfileFps30 = 30;
const int c1ProfileFps60 = 60;
const List<int> c1ProfileFpsOptions = <int>[c1ProfileFps30, c1ProfileFps60];
const String c1ProfileProxyRes = "720p";
const int c1ProfileProxyKbps = 2000;
const int c1ProfileSegmentS = 6;

// Preview constants
const int c1PreviewWidth = 640;
const int c1PreviewHeight = 360;
const int c1PreviewFps = 20;
const int c1PreviewKbpsMin = 1;
const int c1PreviewKbpsMax = 1000;

// Signal ids
const String c1SignalCountdown = "countdown";
const String c1SignalRecStart = "rec.start";
const String c1SignalRecStop = "rec.stop";
const String c1SignalMarkerAck = "marker.ack";
const String c1SignalLeaseWarn = "lease.warn";
const String c1SignalError = "error";
const String c1SignalSyncFlash = "sync.flash";
const List<String> c1SignalIds = <String>[
  c1SignalCountdown,
  c1SignalRecStart,
  c1SignalRecStop,
  c1SignalMarkerAck,
  c1SignalLeaseWarn,
  c1SignalError,
  c1SignalSyncFlash,
];

// Gesture ids
const String c1GestureReview = "review";
const String c1GestureHighlight = "highlight";
const List<String> c1GestureIds = <String>[c1GestureReview, c1GestureHighlight];
