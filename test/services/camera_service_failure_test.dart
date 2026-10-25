import "dart:async";
import "dart:io";

// ignore: depend_on_referenced_packages
import "package:camera_platform_interface/camera_platform_interface.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/camera_capture_settings.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/log_service.dart";
import "package:hydracam/services/manual_exposure_service.dart";
import "package:hydracam/services/recorded_video_snapshots.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/settings_service.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform originalPlatform;
  late MockStorageService storageService;
  final _TestPathProviderPlatform pathProvider = _TestPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    SharedPreferences.setMockInitialValues({});
    storageService = MockStorageService();
    when(() => storageService.isRecordingBlocked).thenReturn(false);
    when(() => storageService.dispose()).thenReturn(null);
    LogService.instance.clearLogs();
  });

  tearDown(() {
    CameraPlatform.instance = originalPlatform;
    LogService.instance.clearLogs();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test("takePhoto surfaces camera failures instead of returning a fake path",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform(cameras: const []);
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.takePhoto(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("No cameras available"),
        ),
      ),
    );
  });

  test("startRecordingVideo stays inactive when the camera platform fails",
      () async {
    final closed = Completer<void>();
    var disposals = 0;
    CameraPlatform.instance = _FakeCameraPlatform(
      startRecordingError: PlatformException(
        code: "ios_camera_start_failed",
        message: "Simulated iPad recording start failure",
      ),
      stopRecordingError: PlatformException(
          code: "RECORDING_STOP_UNCONFIRMED", message: "Unknown retry"),
      stopErrorAfterStarts: 2,
      onEvent: (event) {
        if (event == "dispose" && ++disposals == 2) {
          closed.complete();
        }
      },
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.startRecordingVideo(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("Simulated iPad recording start failure"),
        ),
      ),
    );

    expect(cameraService.isRecording, isFalse);
    final platform = CameraPlatform.instance as _FakeCameraPlatform;
    final dispatched = platform.recordingStarts;
    await expectLater(
        cameraService.startRecordingVideo(),
        throwsA(isA<StateError>().having((error) => error.message, "message",
            contains("Original recording"))));
    expect(platform.recordingStarts, dispatched,
        reason: "Unconfirmed start must retain its original native owner");
    await closed.future.timeout(const Duration(seconds: 1));
    expect(platform.recordingStops, 2,
        reason: "Failed FPS retry must request original STOP automatically");
    await cameraService.stopCamera();
  });

  test("startRecordingVideo works when the iPad has no flash capability",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform(
      setFlashModeError: PlatformException(
        code: "setFlashModeFailed",
        message: "Device does not have flash capabilities",
      ),
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.startRecordingVideo();

    expect(cameraService.isRecording, isTrue);
    expect(
      LogService.instance.logs.any((entry) =>
          entry["message"].toString().contains("Flash is unavailable")),
      isTrue,
    );
  });

  for (final nextPreset in [ExposurePreset.auto, ExposurePreset.shutter1_60]) {
    test(
        "failed exposure cleanup blocks ${nextPreset.storageValue} before camera replacement",
        () async {
      const channel = MethodChannel("hydracam-retained-exposure-test");
      var releaseFails = true;
      var releases = 0;
      final appliedOwners = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == "release") {
          releases++;
          return {"status": releaseFails ? "error" : "released"};
        }
        if (call.method == "applyLock") {
          appliedOwners.add((call.arguments as Map)["ownerId"]);
        }
        return {"status": call.method == "applyLock" ? "locked" : "ok"};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final platform = _FakeCameraPlatform(
        startRecordingError: PlatformException(
            code: "forced_start_failure", message: "forced start failure"),
      );
      CameraPlatform.instance = platform;
      final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel),
      );
      await expectLater(service.startRecordingVideo(), throwsException);
      expect(releases, greaterThan(0));
      await service.stopCamera();
      final createsBeforeRetry = platform.createdCameras;
      final startsBeforeRetry = platform.recordingStarts;
      final disposalsBeforeRetry = platform.disposedCameras;
      final originalCamera = platform.lastCreatedCamera;
      final originalSettings = platform.lastMediaSettings;
      final locksBeforeRetry = appliedOwners.length;
      platform.startRecordingError = null;
      await SettingsService.setExposurePreset(nextPreset);

      await expectLater(
          service.startRecordingVideo(),
          throwsA(isA<Exception>().having((error) => error.toString(),
              "message", contains("Exposure cleanup"))));
      expect(service.isRecording, isFalse);
      expect(platform.createdCameras, createsBeforeRetry + 1,
          reason: "Only the saved original preview may reactivate for restore");
      expect(platform.lastCreatedCamera, originalCamera);
      expect(platform.lastMediaSettings?.resolutionPreset,
          originalSettings?.resolutionPreset);
      expect(platform.lastMediaSettings?.fps, originalSettings?.fps);
      expect(appliedOwners.length, locksBeforeRetry,
          reason: "Recovery cannot create another exposure lease");
      expect(platform.disposedCameras, disposalsBeforeRetry + 1,
          reason: "Failed recovery must close the saved preview again");
      expect(platform.recordingStarts, startsBeforeRetry);

      releaseFails = false;
      await service.startRecordingVideo();
      expect(service.isRecording, isTrue);
      expect(platform.recordingStarts, startsBeforeRetry + 1);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await service.stopCamera();
    });
  }

  for (final restoreSucceeds in [true, false]) {
    test(
        "FPS fallback restores old exposure before replacement ($restoreSucceeds)",
        () async {
      const channel = MethodChannel("hydracam-fps-owner-test");
      final events = <String>[];
      final owners = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final owner = (call.arguments as Map)["ownerId"].toString();
        if (call.method == "applyLock") {
          owners.add(owner);
          events.add("lock:$owner");
          return {"status": "locked"};
        }
        if (call.method == "release") {
          events.add("release:$owner");
          return {"status": restoreSucceeds ? "released" : "error"};
        }
        return {"status": "ok"};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final platform = _FakeCameraPlatform(
        startRecordingError: PlatformException(
            code: "forced_fps_failure", message: "forced FPS failure"),
        startRecordingFailures: 1,
        onEvent: events.add,
      );
      CameraPlatform.instance = platform;
      final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel),
      );
      if (!restoreSucceeds) {
        await expectLater(service.startRecordingVideo(), throwsException);
        expect(platform.createdCameras, 1);
        expect(platform.recordingStarts, 1);
        expect(events, isNot(contains("dispose")));
        return;
      }
      await service.startRecordingVideo();
      expect(owners.length, greaterThanOrEqualTo(2));
      expect(owners.first, isNot(owners[1]));
      final release = events.indexOf("release:${owners.first}");
      final dispose = events.indexOf("dispose");
      final secondLock = events.indexOf("lock:${owners[1]}");
      final retryStart = events.lastIndexOf("start");
      expect(release, greaterThanOrEqualTo(0));
      expect(dispose, greaterThan(release));
      expect(secondLock, greaterThan(dispose));
      expect(retryStart, greaterThan(secondLock));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await service.stopCamera();
    });
  }

  test("concurrent starts share the same pending exposure owner", () async {
    const channel = MethodChannel("hydracam-concurrent-start-test");
    final applied = Completer<Object?>();
    var locks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == "applyLock") {
        locks++;
        return applied.future;
      }
      return {"status": "released"};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final platform = _FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel));
    final first = service.startRecordingVideo();
    final second = service.startRecordingVideo();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      expect(locks, 1);
      expect(platform.createdCameras, 1);
    } finally {
      applied.complete({"status": "locked"});
      await Future.wait([first, second]);
    }
    expect(platform.recordingStarts, 1);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await service.stopCamera();
  });

  test("start waits for concurrent stop cleanup instead of replacing its owner",
      () async {
    const channel = MethodChannel("hydracam-concurrent-stop-test");
    final released = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => call.method == "release"
                ? await released.future
                : {"status": call.method == "applyLock" ? "locked" : "ok"});
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final platform = _FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel));
    await service.startRecordingVideo();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    var stopDone = false;
    final stopping = service
        .stopRecordingVideo()
        .then<Object?>((v) => v, onError: (Object error) => error)
        .whenComplete(() => stopDone = true);
    var nextStartDone = false;
    final starting = service
        .startRecordingVideo()
        .then<Object?>((_) => null, onError: (Object error) => error)
        .whenComplete(() => nextStartDone = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      expect(nextStartDone, isFalse);
      expect(stopDone, isFalse);
      expect(platform.recordingStarts, 1);
    } finally {
      released.complete({"status": "released"});
      await Future.wait([stopping, starting]);
    }
    // The platform double intentionally returns no media file. This verifies
    // ordering/ownership only, not a saved-video or physical-camera witness.
    expect(await stopping, isA<Exception>());
    expect(await starting, same(await stopping),
        reason:
            "The next start must consume the same acknowledged stop result");
    expect(stopDone, isTrue);
    expect(nextStartDone, isTrue);
    expect(platform.recordingStarts, 1);
  });

  for (final operation in ["settings", "recover", "pending"]) {
    test("retained exposure keeps hardware stop distinct from $operation",
        () async {
      const channel = MethodChannel("hydracam-stopped-owner-test");
      final released = Completer<Object?>();
      final events = <String>[];
      final owners = <String>[];
      final releaseInvocations = <({Object? owner, bool retry})>[];
      var retryCleanup = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == "release") {
          final owner = (call.arguments as Map)["ownerId"];
          releaseInvocations.add((owner: owner, retry: retryCleanup));
          LogService.instance.registerLog(
              "Recovery fixture release owner=$owner retry=$retryCleanup "
              "ackCompleted=${released.isCompleted}");
          if (retryCleanup) {
            unawaited(released.future.then<void>((value) {
              LogService.instance.registerLog(
                  "Recovery fixture native ACK owner=$owner value=$value");
            }));
          }
          return retryCleanup ? await released.future : {"status": "error"};
        }
        if (call.method == "applyLock") {
          owners.add((call.arguments as Map)["ownerId"] as String);
          return {"status": "locked"};
        }
        return {"status": "ok"};
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final platform = _FakeCameraPlatform(
        startRecordingError: PlatformException(
            code: "forced_start_failure", message: "forced start failure"),
        onEvent: events.add,
      );
      CameraPlatform.instance = platform;
      final service = CameraService(
          storageService: storageService,
          manualExposureService: ManualExposureService(channel: channel));
      await expectLater(service.startRecordingVideo(), throwsException);
      platform.startRecordingError = null;
      if (operation == "settings") {
        await expectLater(
            service.applyCaptureSettings(
                videoProfile: VideoCaptureProfile.compat720p30),
            throwsA(isA<StateError>().having((error) => error.message,
                "message", contains("Exposure cleanup"))));
        expect(events.where((event) => event == "dispose"), isEmpty);
        return;
      }
      await service.stopCamera();
      expect(events.where((event) => event == "dispose"), hasLength(1),
          reason: "Explicit hardware stop must not wait forever for restore");
      final oldOwner = owners.single;
      final startsBeforeRecovery = platform.recordingStarts;
      retryCleanup = true;
      final starting = service
          .startRecordingVideo()
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      try {
        expect(platform.createdCameras, 2,
            reason: "Reactivate original control without starting an encoder");
        expect(platform.lastCreatedCamera?.name, "fake-back-camera");
        expect(platform.recordingStarts, startsBeforeRecovery);
        expect(owners, [oldOwner], reason: "No new lease before restore ACK");
        expect(
            releaseInvocations.any((invocation) =>
                invocation.retry && invocation.owner == oldOwner),
            isTrue,
            reason:
                "Recovery must dispatch restoration for the original owner");
        if (operation == "pending") {
          expect(await starting, isA<Exception>());
          expect(events.where((event) => event == "dispose"), hasLength(2),
              reason: "Unsettled recovery must close hardware again");
          expect(platform.recordingStarts, startsBeforeRecovery);
        } else {
          released.complete({"status": "released"});
          expect(await starting, isNull);
          expect(service.isRecording, isTrue);
          expect(owners.last, isNot(oldOwner));
        }
      } finally {
        if (!released.isCompleted) {
          released.complete({"status": "released"});
        }
        await starting;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await service.stopCamera();
      }
    });
  }

  test("explicit stop invalidates a start before it can reopen the camera",
      () async {
    const channel = MethodChannel("hydracam-stop-pending-start-test");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async =>
                {"status": call.method == "applyLock" ? "locked" : "released"});
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final platform = _FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel));
    final starting = service
        .startRecordingVideo()
        .then<Object?>((_) => null, onError: (Object error) => error);
    await service.stopCamera();
    expect(await starting, isA<Exception>());
    expect(platform.createdCameras, 0);
    expect(platform.recordingStarts, 0);
  });

  test("a hung exposure read cannot delay the native recording stop", () async {
    const channel = MethodChannel("hydracam-stop-read-test");
    final sensor = Completer<Object?>();
    var readReturned = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == "readCaptureSettings") {
        final value = await sensor.future;
        readReturned = true;
        return value;
      }
      return {"status": call.method == "applyLock" ? "locked" : "released"};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final platform = _FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService,
        manualExposureService: ManualExposureService(channel: channel));
    await service.startRecordingVideo();
    final stopping = service
        .stopRecordingVideo()
        .then<Object?>((value) => value, onError: (Object error) => error);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    try {
      expect(platform.recordingStops, 1,
          reason: "A sensor timeout must not keep the encoder running");
      expect(readReturned, isFalse,
          reason: "Native STOP must precede the actual sensor reply");
    } finally {
      sensor.complete({"status": "ok"});
      await stopping;
      await service.stopCamera();
    }
  });

  test("hardware stop finalizes the original start that replies late",
      () async {
    final started = Completer<void>();
    final events = <String>[];
    final platform = _FakeCameraPlatform(
        startRecordingReply: started.future, onEvent: events.add);
    CameraPlatform.instance = platform;
    final service = CameraService(storageService: storageService);
    final starting = service
        .startRecordingVideo()
        .then<Object?>((_) => null, onError: (Object error) => error);
    while (platform.recordingStarts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final stopping = service.stopCamera();
    await Future<void>.delayed(Duration.zero);
    expect(events, isNot(contains("dispose")),
        reason: "An unpatched platform must stop before native disposal");
    started.complete();
    await stopping;
    await starting;
    expect(platform.recordingStops, 1);
    expect(events.indexOf("stop"), lessThan(events.indexOf("dispose")));
    expect(service.isRecording, isFalse);
  });

  test("failed start automatically closes hardware without a reachable UI STOP",
      () async {
    final rawStart = Completer<void>();
    final closed = Completer<void>();
    final platform = _FakeCameraPlatform(
        startRecordingReply: rawStart.future,
        onEvent: (event) {
          if (event == "dispose" && !closed.isCompleted) {
            closed.complete();
          }
        });
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService,
        cameraOperationTimeout: const Duration(milliseconds: 50));
    try {
      await expectLater(service.startRecordingVideo(), throwsException);
      expect(service.isRecording, isFalse);
      await closed.future.timeout(const Duration(seconds: 1));
      expect(platform.recordingStarts, 1);
      rawStart.complete();
      await Future<void>.delayed(Duration.zero);
      expect(platform.recordingStops, 0,
          reason: "Never send a global generic/iOS STOP after disposal");
      await expectLater(
          service.startRecordingVideo(),
          throwsA(isA<StateError>().having((error) => error.message, "message",
              contains("Original recording"))));
    } finally {
      if (!rawStart.isCompleted) {
        rawStart.complete();
      }
      await service.stopCamera();
    }
  });

  test("an unconfirmed native stop retains ownership before another capture",
      () async {
    final platform = _FakeCameraPlatform(
        stopRecordingError: PlatformException(
            code: "RECORDING_STOP_UNCONFIRMED", message: "Still owned"));
    CameraPlatform.instance = platform;
    final service = CameraService(storageService: storageService);
    await service.startRecordingVideo();
    await expectLater(service.stopRecordingVideo(), throwsA(isA<Exception>()));
    final starts = platform.recordingStarts;
    await expectLater(
        service.startRecordingVideo(),
        throwsA(isA<StateError>().having((error) => error.message, "message",
            contains("Original recording"))));
    expect(platform.recordingStarts, starts);
    platform.stopRecordingError = null;
    await service.stopCamera();
  });

  for (final code in [
    "RECORDING_NOT_STARTED",
    "RECORDING_FINALIZED_WITHOUT_PATH"
  ]) {
    test("typed CameraX terminal $code permits the next owner", () async {
      final platform = _FakeCameraPlatform(
          stopRecordingError: CameraException(code, "Terminal acknowledged"));
      CameraPlatform.instance = platform;
      final service = CameraService(storageService: storageService);
      await service.startRecordingVideo();
      await expectLater(
          service.stopRecordingVideo(), throwsA(isA<Exception>()));
      platform.stopRecordingError = null;
      await service.startRecordingVideo();
      expect(platform.recordingStarts, 2);
      await service.stopCamera();
    });
  }

  test("receipt failure retains the original native file for a metadata retry",
      () async {
    final directory = await Directory.systemTemp.createTemp("receipt-fault-");
    final store = _FailingReceiptStore(directory);
    final platform = _FakeCameraPlatform();
    CameraPlatform.instance = platform;
    final service = CameraService(
        storageService: storageService, recordedVideoSnapshots: store);
    try {
      await service.startRecordingVideo();
      await expectLater(
          service.stopRecordingVideo(), throwsA(isA<Exception>()));
      await expectLater(
          service.startRecordingVideo(),
          throwsA(isA<StateError>().having((error) => error.message, "message",
              contains("Original recording"))));
      await expectLater(
          service.stopRecordingVideo(), throwsA(isA<Exception>()));
      expect(platform.recordingStops, 1,
          reason: "Metadata retry must not stop another native recording");
      expect((await store.forPath("unused-video.mp4"))?.sourcePath,
          "unused-video.mp4");
      await service.startRecordingVideo();
      expect(platform.recordingStarts, 2);
      await service.stopCamera();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test("STOP during FPS recovery prevents the replacement encoder dispatch",
      () async {
    var creates = 0;
    Future<void>? stopping;
    late CameraService service;
    final platform = _FakeCameraPlatform(
        startRecordingError: PlatformException(
            code: "forced_fps_failure", message: "FPS failed"),
        startRecordingFailures: 1,
        onEvent: (event) {
          if (event == "create" && ++creates == 2) {
            stopping = service.stopCamera();
          }
        });
    CameraPlatform.instance = platform;
    service = CameraService(storageService: storageService);
    await expectLater(service.startRecordingVideo(), throwsA(isA<Exception>()));
    await stopping;
    expect(platform.recordingStarts, 1);
    expect(service.isRecording, isFalse);
  });

  test("non-flash initialization failures still surface", () async {
    CameraPlatform.instance = _FakeCameraPlatform(
      setFlashModeError: PlatformException(
        code: "setFlashModeFailed",
        message: "Camera session is unavailable",
      ),
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await expectLater(
      cameraService.ensureCameraIsReady(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("Camera session is unavailable"),
        ),
      ),
    );
  });

  test("stopRecordingVideo surfaces the camera plugin no-recording error",
      () async {
    CameraPlatform.instance = _FakeCameraPlatform();
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.ensureCameraIsReady();

    await expectLater(
      cameraService.stopRecordingVideo(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("stopVideoRecording was called when no video is recording"),
        ),
      ),
    );

    expect(cameraService.isRecording, isFalse);
  });

  test("mock camera writes placeholder media without a platform camera",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "mock-camera-session",
      "mock-camera-session",
      deviceType: "Master",
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    try {
      await cameraService.initAvailableCameras();
      final photoPath = await cameraService.takePhoto();
      await cameraService.startRecordingVideo();
      final videoPath = await cameraService.stopRecordingVideo();

      expect(cameraService.isUsingMockCamera, isTrue);
      expect(cameraService.controller, isNull);
      expect(cameraService.deviceCameras, hasLength(1));
      expect(File(photoPath).existsSync(), isTrue);
      expect(File(videoPath).existsSync(), isTrue);
      expect(cameraService.isRecording, isFalse);
    } finally {
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
    }
  });

  test("mock camera refuses to write media without an active service session",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    await cameraService.initAvailableCameras();

    await expectLater(
      cameraService.takePhoto(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("No active service session"),
        ),
      ),
    );
    await cameraService.startRecordingVideo();
    await expectLater(
      cameraService.stopRecordingVideo(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          "message",
          contains("No active service session"),
        ),
      ),
    );

    final documentsPath = await pathProvider.getApplicationDocumentsPath();
    final sessionNullDirectory = Directory("$documentsPath/session_null");
    expect(sessionNullDirectory.existsSync(), isFalse);
    expect(cameraService.isRecording, isFalse);
  });

  test("critical battery force stop saves mock recording and interrupts",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "critical-battery-force-stop",
      "critical-battery-force-stop",
      deviceType: "Master",
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    try {
      await cameraService.initAvailableCameras();
      await cameraService.startRecordingVideo();

      await cameraService.forceStopRecordingDueToBattery();

      final videos =
          SessionManager.instance.currentSession?.capturedVideos ?? [];
      expect(cameraService.isRecording, isFalse);
      expect(cameraService.recordingInterrupted.value, isTrue);
      expect(videos, hasLength(1));
      expect(File(videos.single.videoPath).existsSync(), isTrue);
      verify(() => storageService.showNotification(
          "Recording stopped due to critical battery.")).called(1);
      expect(
        LogService.instance.logs.any((entry) => entry["message"]
            .toString()
            .contains("Stopping recording due to critical battery.")),
        isTrue,
      );
    } finally {
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
    }
  });

  test("forced stop rechecks original session after device identity resolves",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance
        .startSession("original", "original", deviceType: "Master");
    final requested = Completer<void>();
    final identity = Completer<String>();
    final service = _StoppedMetadataCamera(
        storageService: storageService,
        deviceIdProvider: () {
          requested.complete();
          return identity.future;
        });
    await service.startRecordingVideo();
    final stopping = service.forceStopRecordingDueToBattery();
    await requested.future;
    await SessionManager.instance.endSession();
    SessionManager.instance
        .startSession("replacement", "replacement", deviceType: "Master");
    identity.complete("existing-device");
    try {
      await stopping;
      expect(SessionManager.instance.currentSession?.capturedVideos, isEmpty);
      expect(service.acknowledged, isFalse);
    } finally {
      await SessionManager.instance.endSession();
    }
  });

  test("critical storage force stop saves mock recording and interrupts",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "critical-storage-force-stop",
      "critical-storage-force-stop",
      deviceType: "Master",
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    try {
      await cameraService.initAvailableCameras();
      await cameraService.startRecordingVideo();

      await cameraService.forceStopRecordingDueToStorage();

      final videos =
          SessionManager.instance.currentSession?.capturedVideos ?? [];
      expect(cameraService.isRecording, isFalse);
      expect(cameraService.recordingInterrupted.value, isTrue);
      expect(videos, hasLength(1));
      expect(File(videos.single.videoPath).existsSync(), isTrue);
      verify(() => storageService
          .showNotification("Recording stopped due to low storage.")).called(1);
      expect(
        LogService.instance.logs.any((entry) => entry["message"]
            .toString()
            .contains("Stopping recording due to critical storage.")),
        isTrue,
      );
    } finally {
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
    }
  });

  test("critical battery force stop survives missing start timestamp",
      () async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    SessionManager.instance.startSession(
      "critical-battery-missing-start",
      "critical-battery-missing-start",
      deviceType: "Master",
    );
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: true,
    );

    try {
      await cameraService.initAvailableCameras();
      await cameraService.startRecordingVideo();
      cameraService.videoStartRecordingDate = null;

      await cameraService.forceStopRecordingDueToBattery();

      final videos =
          SessionManager.instance.currentSession?.capturedVideos ?? [];
      expect(cameraService.isRecording, isFalse);
      expect(cameraService.recordingInterrupted.value, isTrue);
      expect(videos, hasLength(1));
      expect(videos.single.startRecordingDate, isNotNull);
      expect(videos.single.endRecordingDate, isNotNull);
    } finally {
      if (SessionManager.instance.isSessionActive) {
        await SessionManager.instance.endSession();
      }
    }
  });

  test("selected ultra-wide lens uses sport 1080p60 controller settings",
      () async {
    final fakePlatform = _FakeCameraPlatform(
      cameras: const [
        CameraDescription(
          name: "iphone-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.wide,
        ),
        CameraDescription(
          name: "iphone-ultra-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.ultraWide,
        ),
      ],
    );
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "cameraLensPreference": LensPreference.ultraWide.storageValue,
      "videoCaptureProfile": VideoCaptureProfile.sport1080p60.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.startRecordingVideo();

    expect(fakePlatform.lastCreatedCamera?.name, "iphone-ultra-wide");
    expect(
      fakePlatform.lastMediaSettings?.resolutionPreset,
      ResolutionPreset.veryHigh,
    );
    expect(fakePlatform.lastMediaSettings?.fps, 60);
  });

  test("changing video profile preserves the selected camera", () async {
    final fakePlatform = _FakeCameraPlatform(
      cameras: const [
        CameraDescription(
          name: "iphone-wide",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.wide,
        ),
        CameraDescription(
          name: "iphone-telephoto",
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.telephoto,
        ),
      ],
    );
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "selectedCameraName": "iphone-telephoto",
      "videoCaptureProfile": VideoCaptureProfile.standard1080p30.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.ensureCameraIsReady();
    await cameraService.setVideoCaptureProfile(VideoCaptureProfile.detail4k30);

    expect(fakePlatform.lastCreatedCamera?.name, "iphone-telephoto");
    expect(
      fakePlatform.lastMediaSettings?.resolutionPreset,
      ResolutionPreset.ultraHigh,
    );
    expect(fakePlatform.lastMediaSettings?.fps, 30);
  });

  test("setup preview uses preset defaults without explicit fps", () async {
    final fakePlatform = _FakeCameraPlatform();
    CameraPlatform.instance = fakePlatform;
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.prepareCameraPreview();

    expect(fakePlatform.lastMediaSettings?.resolutionPreset,
        ResolutionPreset.veryHigh);
    expect(fakePlatform.lastMediaSettings?.fps, isNull);
  });

  test("Samsung S7 edge keeps requested profile without explicit fps",
      () async {
    final fakePlatform = _FakeCameraPlatform();
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "videoCaptureProfile": VideoCaptureProfile.standard1080p30.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
      deviceInfoProvider: () async => {
        "manufacturer": "samsung",
        "brand": "samsung",
        "model": "SM-G935F",
        "version.sdkInt": 26,
      },
    );

    await cameraService.ensureCameraIsReady();

    expect(fakePlatform.lastMediaSettings?.resolutionPreset,
        ResolutionPreset.veryHigh);
    expect(fakePlatform.lastMediaSettings?.fps, isNull);
    expect(cameraService.currentProfile, VideoCaptureProfile.standard1080p30);
    expect(
      LogService.instance.logs.any((entry) => entry["message"]
          .toString()
          .contains("Samsung S7 edge compatibility mode")),
      isTrue,
    );
  });

  test("non-S7 Android keeps requested explicit fps profile", () async {
    final fakePlatform = _FakeCameraPlatform();
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "videoCaptureProfile": VideoCaptureProfile.standard1080p30.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
      deviceInfoProvider: () async => {
        "manufacturer": "samsung",
        "brand": "samsung",
        "model": "SM-G970F",
        "version.sdkInt": 31,
      },
    );

    await cameraService.ensureCameraIsReady();

    expect(fakePlatform.lastMediaSettings?.resolutionPreset,
        ResolutionPreset.veryHigh);
    expect(fakePlatform.lastMediaSettings?.fps, 30);
    expect(cameraService.currentProfile, VideoCaptureProfile.standard1080p30);
  });

  test("recording after setup preview rebuilds the explicit fps controller",
      () async {
    final fakePlatform = _FakeCameraPlatform();
    CameraPlatform.instance = fakePlatform;
    SharedPreferences.setMockInitialValues({
      "videoCaptureProfile": VideoCaptureProfile.sport1080p60.storageValue,
    });
    final cameraService = CameraService(
      storageService: storageService,
      useMockCamera: false,
    );

    await cameraService.prepareCameraPreview();
    expect(fakePlatform.lastMediaSettings?.fps, isNull);

    await cameraService.startRecordingVideo();

    expect(fakePlatform.lastMediaSettings?.resolutionPreset,
        ResolutionPreset.veryHigh);
    expect(fakePlatform.lastMediaSettings?.fps, 60);
    expect(cameraService.isRecording, isTrue);
  });

  test("macOS runtime uses the real camera backend unless mock is explicit",
      () async {
    final cameraService = CameraService(storageService: storageService);

    expect(cameraService.isUsingMockCamera, isFalse);
  });
}

class _StoppedMetadataCamera extends CameraService {
  _StoppedMetadataCamera(
      {required super.storageService, required super.deviceIdProvider})
      : super(useMockCamera: true);

  bool acknowledged = false;

  @override
  Future<String> stopRecordingVideo() async => "opaque-sdk-return-path";

  @override
  Future<RecordedVideoSnapshot> snapshotForRecordedVideo(String path) async =>
      RecordedVideoSnapshot.capture(
          captureId: "original-capture",
          path: path,
          startedAt: DateTime.utc(2026, 10, 25),
          stoppedAt: DateTime.utc(2026, 10, 25, 0, 0, 1),
          context: null,
          sessionGuid: "original");

  @override
  Future<void> acknowledgeRecordedVideo(RecordedVideoSnapshot snapshot) async {
    acknowledged = true;
  }
}

class _FailingReceiptStore extends RecordedVideoSnapshots {
  _FailingReceiptStore(Directory directory)
      : super(directory: () async => directory);

  int calls = 0;

  @override
  Future<void> remember(RecordedVideoSnapshot snapshot) async {
    if (++calls == 1) {
      throw const FileSystemException("Injected metadata write failure");
    }
    await super.remember(snapshot);
  }
}

class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({
    List<CameraDescription>? cameras,
    this.startRecordingError,
    this.startRecordingFailures,
    this.onEvent,
    this.setFlashModeError,
    this.startRecordingReply,
    this.stopRecordingError,
    this.stopErrorAfterStarts,
  }) : cameras = cameras ??
            const [
              CameraDescription(
                name: "fake-back-camera",
                lensDirection: CameraLensDirection.back,
                sensorOrientation: 90,
              ),
            ];

  final List<CameraDescription> cameras;
  PlatformException? startRecordingError;
  int? startRecordingFailures;
  final void Function(String)? onEvent;
  final PlatformException? setFlashModeError;
  final Future<void>? startRecordingReply;
  Exception? stopRecordingError;
  final int? stopErrorAfterStarts;
  final StreamController<CameraErrorEvent> _errorController =
      StreamController<CameraErrorEvent>.broadcast();
  CameraDescription? lastCreatedCamera;
  MediaSettings? lastMediaSettings;

  bool _isRecording = false;
  int _nextCameraId = 1;
  int createdCameras = 0;
  int recordingStarts = 0;
  int recordingStops = 0;
  int disposedCameras = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    createdCameras++;
    onEvent?.call("create");
    lastCreatedCamera = cameraDescription;
    lastMediaSettings = mediaSettings;
    return _nextCameraId++;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream<CameraInitializedEvent>.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream<CameraClosingEvent>.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errorController.stream;

  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
          int cameraId) =>
      const Stream<CameraResolutionChangedEvent>.empty();

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      const Stream<VideoRecordedEvent>.empty();

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    final error = setFlashModeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    recordingStarts++;
    onEvent?.call("start");
    await startRecordingReply;
    final error = startRecordingError;
    if (error != null &&
        (startRecordingFailures == null || startRecordingFailures! > 0)) {
      if (startRecordingFailures != null) {
        startRecordingFailures = startRecordingFailures! - 1;
      }
      throw error;
    }
    _isRecording = true;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    recordingStops++;
    onEvent?.call("stop");
    final error = stopRecordingError;
    if (error != null &&
        (stopErrorAfterStarts == null ||
            recordingStarts >= stopErrorAfterStarts!)) {
      throw error;
    }
    if (!_isRecording) {
      throw PlatformException(
        code: "RECORDING_NOT_STARTED",
        message: "stopVideoRecording was called when no video is recording.",
      );
    }
    _isRecording = false;
    return XFile("unused-video.mp4");
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile("unused-photo.jpg");

  @override
  Future<void> dispose(int cameraId) async {
    disposedCameras++;
    onEvent?.call("dispose");
  }
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("camera_service_mock_docs");
    return _documentsDir!.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
