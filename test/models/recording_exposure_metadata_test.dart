import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/recording_exposure_metadata.dart";

void main() {
  const lock = {
    "status": "locked",
    "exposureTimeNs": 16666667,
    "iso": 400,
    "underexposed": false,
  };
  const start = {
    "status": "ok",
    "source": "camera2_capture_result",
    "exposureTimeNs": 16666667,
    "iso": 400,
    "frameDurationNs": 33333333,
    "fps": 30.0,
    "rollingShutterSkewNs": 22000000,
  };
  const stop = {
    "status": "ok",
    "source": "camera2_capture_result",
    "exposureTimeNs": 16666000,
    "iso": 401,
    "frameDurationNs": 33333000,
    "fps": 30.0,
  };

  group("RecordingExposureMetadata", () {
    test("reads summary values from the start snapshot", () {
      final exposure = RecordingExposureMetadata.fromSnapshots(
        preset: "shutter1_60",
        lockStatus: "locked",
        requestedExposureTimeNs: 16666667,
        lock: lock,
        start: start,
        stop: stop,
      );

      expect(exposure.isLocked, isTrue);
      expect(exposure.exposureTimeNs, 16666667);
      expect(exposure.iso, 400);
      expect(exposure.frameDurationNs, 33333333);
      expect(exposure.framesPerSecond, 30.0);
      expect(exposure.rollingShutterSkewNs, 22000000);
      expect(exposure.underexposed, isFalse);
      expect(exposure.source, "camera2_capture_result");
    });

    test("falls back to the stop snapshot when start has no result", () {
      final exposure = RecordingExposureMetadata.fromSnapshots(
        preset: "auto",
        lockStatus: "auto",
        start: {"status": "no_capture_result"},
        stop: stop,
      );

      expect(exposure.exposureTimeNs, 16666000);
      expect(exposure.iso, 401);
      expect(exposure.rollingShutterSkewNs, isNull);
    });

    test("round-trips through JSON", () {
      final exposure = RecordingExposureMetadata.fromSnapshots(
        preset: "shutter1_120",
        lockStatus: "locked",
        requestedExposureTimeNs: 8333333,
        lock: lock,
        start: start,
        stop: stop,
      );

      final restored = RecordingExposureMetadata.fromJson(exposure.toJson());

      expect(restored?.toJson(), exposure.toJson());
      expect(exposure.toJson(), containsPair("fps", 30.0));
    });

    test("ignores JSON without a preset", () {
      expect(RecordingExposureMetadata.fromJson({"iso": 100}), isNull);
      expect(RecordingExposureMetadata.fromJson(null), isNull);
    });
  });

  group("MediaCaptureContext exposure", () {
    test("withExposure keeps context fields and serializes exposure", () {
      final context = MediaCaptureContext.fromJson({
        "cameraPerspectiveId": "tin_back_floor_center",
        "cameraName": "2",
        "videoCaptureProfile": "detail4k30",
        "deviceId": "phone-a",
      })!;
      final exposure = RecordingExposureMetadata.fromSnapshots(
        preset: "shutter1_60",
        lockStatus: "locked",
        start: start,
      );

      final json = context.withExposure(exposure).toJson();
      final restored = MediaCaptureContext.fromJson(json);

      expect(json["cameraName"], "2");
      expect(json["videoCaptureProfile"], "detail4k30");
      expect(json["exposure"], containsPair("preset", "shutter1_60"));
      expect(restored?.exposure?.iso, 400);
    });

    test("omits exposure for contexts without it", () {
      final context = MediaCaptureContext.fromJson({
        "cameraName": "0",
        "deviceId": "phone-a",
      })!;

      expect(context.exposure, isNull);
      expect(context.toJson().containsKey("exposure"), isFalse);
    });
  });
}
