import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";
import "package:hydracam/services/manual_exposure_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("hydracam-test/manual_exposure");
  late List<MethodCall> calls;

  void handle(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  RecordingExposureSession session(ExposurePreset preset) {
    return RecordingExposureSession(
      service: ManualExposureService(channel: channel),
      preset: preset,
      cameraName: "2",
      frameDurationNs: 33333333,
      settleDelay: Duration.zero,
    );
  }

  setUp(() {
    calls = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test("ExposurePreset defaults to 1/60 s and maps shutter times", () {
    expect(ExposurePreset.fromStorageValue(null), ExposurePreset.shutter1_60);
    expect(ExposurePreset.fromStorageValue("auto"), ExposurePreset.auto);
    expect(ExposurePreset.shutter1_30.exposureTimeNs, 33333333);
    expect(ExposurePreset.shutter1_120.exposureTimeNs, 8333333);
    expect(ExposurePreset.auto.isManual, isFalse);
  });

  test("manual preset locks, relocks after start, samples and releases",
      () async {
    handle((call) async {
      return switch (call.method) {
        "applyLock" => {"status": "locked", "iso": 400, "underexposed": false},
        "readCaptureSettings" => {
            "status": "ok",
            "exposureTimeNs": 8333333,
            "iso": 400,
            "frameDurationNs": 33333333,
            "fps": 30.0,
            "rollingShutterSkewNs": 21000000,
          },
        "release" => {"status": "released"},
        _ => null,
      };
    });

    final exposure = session(ExposurePreset.shutter1_120);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    await exposure.readBeforeStop();
    final metadata = await exposure.finish();

    expect(calls.map((call) => call.method), [
      "applyLock",
      "applyLock",
      "readCaptureSettings",
      "readCaptureSettings",
      "release",
    ]);
    expect(calls.first.arguments, {
      "cameraName": "2",
      "exposureTimeNs": 8333333,
      "frameDurationNs": 33333333,
    });
    expect(metadata.lockStatus, "locked");
    expect(metadata.requestedExposureTimeNs, 8333333);
    expect(metadata.exposureTimeNs, 8333333);
    expect(metadata.rollingShutterSkewNs, 21000000);
    expect(metadata.lock, containsPair("relockAfterStartStatus", "locked"));
  });

  test("auto preset only samples the sensor", () async {
    handle((call) async => {"status": "ok", "exposureTimeNs": 10000000});

    final exposure = session(ExposurePreset.auto);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    await exposure.readBeforeStop();
    final metadata = await exposure.finish();

    expect(calls.map((call) => call.method),
        ["readCaptureSettings", "readCaptureSettings"]);
    expect(metadata.lockStatus, "auto");
    expect(metadata.exposureTimeNs, 10000000);
  });

  test("unsupported camera records the status and never releases", () async {
    handle((call) async => call.method == "applyLock"
        ? {"status": "unsupported", "cameraId": "2"}
        : {"status": "ok"});

    final exposure = session(ExposurePreset.shutter1_60);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    await exposure.readBeforeStop();
    final metadata = await exposure.finish();

    expect(metadata.lockStatus, "unsupported");
    expect(calls.where((call) => call.method == "release"), isEmpty);
    expect(calls.where((call) => call.method == "applyLock"), hasLength(1));
  });

  test("missing platform channel degrades to unavailable", () async {
    final exposure = session(ExposurePreset.shutter1_60);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    await exposure.readBeforeStop();
    final metadata = await exposure.finish();

    expect(metadata.lockStatus, "unavailable");
    expect(metadata.exposureTimeNs, isNull);
  });

  test("abort releases a lock once", () async {
    handle((call) async =>
        {"status": call.method == "applyLock" ? "locked" : "released"});

    final exposure = session(ExposurePreset.shutter1_30);
    await exposure.lockBeforeStart();
    await exposure.abort();
    await exposure.abort();

    expect(calls.where((call) => call.method == "release"), hasLength(1));
  });
}
