import "package:flutter_test/flutter_test.dart";
import "package:hydracam/court/c1_contract_constants.dart";

void main() {
  test("C1 contract version and patterns match expected 1.29 contract", () {
    expect(c1ProtocolVersion, 1);
    expect(c1ContractVersion, "1.29");
    expect(
        RegExp(c1ContractVersionPattern).hasMatch(c1ContractVersion), isTrue);
    expect(RegExp(c1ContractVersionPattern).hasMatch("1"), isFalse);

    expect(c1StreamIdMaxBytes, 512);
    const validToken = "a123456789012345678901";
    expect(
      RegExp(c1StreamIdPattern).hasMatch(
        "publish:court/court-1/center:device:$validToken",
      ),
      isTrue,
    );
    expect(RegExp(c1PublishTokenPattern).hasMatch(validToken), isTrue);
    expect(RegExp(c1PublishTokenPattern).hasMatch("short"), isFalse);
    expect(
      RegExp(c1Sha256Pattern).hasMatch("0123456789abcdef" * 4),
      isTrue,
    );
  });

  test("message types, nack codes, and modes stay consistent", () {
    expect(c1BidirectionalMessageTypes, [c1MsgAck, c1MsgNack]);
    expect(c1DeviceMessageTypes, containsAll(c1BidirectionalMessageTypes));
    expect(c1CloudMessageTypes, containsAll(c1BidirectionalMessageTypes));
    expect(
      c1AllMessageTypes,
      containsAll([
        c1MsgHello,
        c1MsgState,
        c1MsgClockPing,
        c1MsgClockPong,
        c1MsgRecordingStarted,
        c1MsgRecordingSegment,
        c1MsgRecordingStopped,
        c1MsgRecordingGap,
        c1MsgGestureDetected,
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
      ]),
    );
    expect(c1AllMessageTypes.toSet().length, c1AllMessageTypes.length);

    expect(
      c1NackCodes,
      [
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
      ],
    );

    expect(c1DeviceModes, C1DeviceMode.values.map((m) => m.wire).toList());
    expect(c1BlockedReasons, [c1BlockedStorageFull]);
    expect(c1Tiers, [c1TierProxy, c1TierMaster]);
    expect(c1GapReasons, [c1GapReasonNoCompleteFrame]);
    expect(
      c1MasterModes,
      [
        c1MasterModeNever,
        c1MasterModeOnRequest,
        c1MasterModeWindow,
        c1MasterModeStream
      ],
    );
  });

  test("capture, profile, preview, signal, and gesture constants match", () {
    expect(c1Lenses, [c1LensWide, c1LensUltrawide, c1LensTele]);
    expect(c1VideoCodecs, [c1VideoCodecAvc, c1VideoCodecHevc]);
    expect(c1RotationDegrees, [0, 90, 180, 270]);

    expect(c1ProfileMasterResolutions, ["2160p", "1080p", "720p"]);
    expect(c1ProfileFpsOptions, [30, 60]);
    expect(c1ProfileProxyRes, "720p");
    expect(c1ProfileProxyKbps, 2000);
    expect(c1ProfileSegmentS, 6);

    expect(c1PreviewWidth, 640);
    expect(c1PreviewHeight, 360);
    expect(c1PreviewFps, 20);
    expect(c1PreviewKbpsMin, 1);
    expect(c1PreviewKbpsMax, 1000);

    expect(
      c1SignalIds,
      [
        c1SignalCountdown,
        c1SignalRecStart,
        c1SignalRecStop,
        c1SignalMarkerAck,
        c1SignalLeaseWarn,
        c1SignalError,
        c1SignalSyncFlash,
      ],
    );
    expect(c1GestureIds, [c1GestureReview, c1GestureHighlight]);
  });
}
