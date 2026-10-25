import "dart:async";

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

  RecordingExposureSession session(ExposurePreset preset,
      {Duration snapshotTimeout = const Duration(seconds: 2)}) {
    return RecordingExposureSession(
      service: ManualExposureService(channel: channel),
      preset: preset,
      cameraName: "2",
      frameDurationNs: 33333333,
      settleDelay: Duration.zero,
      snapshotTimeout: snapshotTimeout,
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

  for (final status in ["error", "unavailable", "unsupported", "no_camera"]) {
    test("failed recording relock reports $status and releases preview lock",
        () async {
      var locks = 0;
      handle((call) async => switch (call.method) {
            "applyLock" => {"status": ++locks == 1 ? "locked" : status},
            "readCaptureSettings" => {
                "status": "ok",
                "exposureTimeNs": 30000000
              },
            "release" => {"status": "released"},
            _ => null,
          });
      final exposure = session(ExposurePreset.shutter1_120);
      await exposure.lockBeforeStart();
      exposure.afterStart();
      await exposure.readBeforeStop();
      final metadata = await exposure.finish();
      await exposure.abort();
      expect(metadata.lockStatus, status);
      expect(metadata.isLocked, isFalse);
      expect(exposure.isLocked, isFalse);
      expect(metadata.lock, containsPair("relockAfterStartStatus", status));
      expect(calls.where((call) => call.method == "release"), hasLength(1));
    });
  }

  test("failed release is recorded and remains eligible for explicit retry",
      () async {
    var releases = 0;
    handle((call) async => switch (call.method) {
          "applyLock" => {"status": "locked"},
          "readCaptureSettings" => {"status": "ok"},
          "release" => {"status": ++releases == 1 ? "error" : "released"},
          _ => null,
        });
    final exposure = session(ExposurePreset.shutter1_60);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    await exposure.readBeforeStop();
    final metadata = await exposure.finish();
    expect(metadata.isLocked, isTrue,
        reason: "Recording and restoration differ");
    expect(metadata.lock, containsPair("releaseStatus", "error"));
    await exposure.abort();
    await exposure.abort();
    expect(calls.where((call) => call.method == "release"), hasLength(2));
    expect(metadata.lock, containsPair("releaseStatus", "error"),
        reason: "A later retry must not rewrite already returned metadata");
  });

  test("concurrent abort calls share one in-flight release", () async {
    final released = Completer<Object?>();
    handle((call) => call.method == "release"
        ? released.future
        : Future.value({"status": "locked"}));
    final exposure = session(ExposurePreset.shutter1_60);
    await exposure.lockBeforeStart();
    var firstDone = false;
    var secondDone = false;
    final first = exposure.abort().then((_) => firstDone = true);
    final second = exposure.abort().then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == "release"), hasLength(1));
    try {
      expect(firstDone, isFalse);
      expect(secondDone, isFalse);
    } finally {
      released.complete({"status": "released"});
      await Future.wait([first, second]);
    }
    expect(firstDone, isTrue);
    expect(secondDone, isTrue);
    expect(calls.where((call) => call.method == "release"), hasLength(1));
  });

  test("a pending recording relock cannot finalize as successfully locked",
      () async {
    final relock = Completer<Object?>();
    var locks = 0;
    handle((call) {
      if (call.method == "applyLock") {
        return ++locks == 1
            ? Future.value({"status": "locked"})
            : relock.future;
      }
      return Future.value(
          {"status": call.method == "release" ? "released" : "ok"});
    });
    final exposure =
        session(ExposurePreset.shutter1_60, snapshotTimeout: Duration.zero);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    final metadata = await exposure.finish();
    try {
      expect(metadata.lockStatus, "unavailable");
      expect(metadata.isLocked, isFalse);
      expect(metadata.start, containsPair("status", "timeout"));
    } finally {
      relock.complete({"status": "error"});
      await Future<void>.delayed(Duration.zero);
    }
  });

  test("a late relock during release cannot change finalized recording status",
      () async {
    final relock = Completer<Object?>();
    final releaseStarted = Completer<void>();
    final released = Completer<Object?>();
    var locks = 0;
    handle((call) {
      if (call.method == "applyLock") {
        return ++locks == 1
            ? Future.value({"status": "locked"})
            : relock.future;
      }
      if (call.method == "release") {
        releaseStarted.complete();
        return released.future;
      }
      return Future.value({"status": "ok"});
    });
    final exposure =
        session(ExposurePreset.shutter1_60, snapshotTimeout: Duration.zero);
    await exposure.lockBeforeStart();
    exposure.afterStart();
    final finishing = exposure.finish();
    await releaseStarted.future;
    relock.complete({"status": "locked"});
    await Future<void>.delayed(Duration.zero);
    released.complete({"status": "released"});
    final metadata = await finishing;
    expect(metadata.lockStatus, "unavailable");
    expect(metadata.isLocked, isFalse);
    expect(metadata.start, containsPair("status", "timeout"));
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
