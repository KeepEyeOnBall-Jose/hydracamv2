import "dart:async";

import "package:camera_android_camerax/camera_android_camerax.dart";
import "package:camera_android_camerax/src/camerax_library.dart";
import "package:camera_platform_interface/camera_platform_interface.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";

// These tests exercise the production plugin with its existing native proxy
// boundary. Paths are opaque SDK return values: no media bytes/files are made,
// and these tests make no physical-camera or playable-video claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_Listener((_, __) {}));
    registerFallbackValue(_VideoCapture());
    registerFallbackValue(<UseCase>[]);
  });

  late _Rig rig;
  setUp(() => rig = _Rig());
  tearDown(() async {
    await rig.settleTestDoubles();
    PigeonOverrides.pigeon_reset();
  });

  test("dispose unbinds immediately and closes a late persistent handle", () async {
    final attempt = rig.plan("/sdk-output/late.mp4", delayHandle: true);
    final starting = rig.start(attempt);
    await attempt.dispatched.future;

    expect(await rig.bounded(rig.watch(rig.camera.dispose(7))), isNull);
    expect(rig.hardwareUnbound, isTrue);
    attempt.returnHandle();

    expect(await rig.bounded(starting), isA<CameraException>());
    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, attempt.path);
    expect(attempt.closeCalls, 1);
  });

  test("Finalize before Start settles failure and retains the terminal path", () async {
    final attempt = rig.plan("/sdk-output/finalize-first.mp4");
    final starting = rig.start(attempt);
    await attempt.dispatched.future;
    attempt.emit(_Finalize());

    expect(await rig.bounded(starting), isA<CameraException>());
    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, attempt.path);
  });

  test("terminal events before the start reply do not lose the original path", () async {
    final attempt = rig.plan("/sdk-output/early-terminal.mp4", delayHandle: true);
    final starting = rig.start(attempt);
    await attempt.dispatched.future;
    attempt.emit(_Start());
    attempt.emit(_Finalize());
    attempt.returnHandle();

    expect(await rig.bounded(starting), isNot(isA<_Pending>()));
    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, attempt.path);
  });

  test("dispose and duplicate stops share one close and terminal result", () async {
    final attempt = rig.plan("/sdk-output/shared.mp4", finalizeOnClose: false);
    await rig.startSuccessfully(attempt);
    final recorded = <VideoRecordedEvent>[];
    final subscription = rig.camera.onVideoRecordedEvent(7).listen(recorded.add);
    addTearDown(subscription.cancel);

    final disposing = rig.watch(rig.camera.dispose(7));
    final first = rig.watch(rig.camera.stopVideoRecording(7));
    final second = rig.watch(rig.camera.stopVideoRecording(7));
    expect(await rig.bounded(disposing), isNull);
    expect(rig.hardwareUnbound, isTrue);
    expect(await rig.bounded(first), isA<_Pending>());
    expect(attempt.closeCalls, 1);
    attempt.emit(_Finalize());

    final a = await rig.bounded(first);
    final b = await rig.bounded(second);
    expect(a, isA<XFile>());
    expect(b, isA<XFile>());
    expect((a as XFile).path, attempt.path);
    expect((b as XFile).path, attempt.path);
    expect(attempt.closeCalls, 1);
    await Future<void>.delayed(Duration.zero);
    expect(recorded, hasLength(1));
  });

  test("same camera cannot encode again before the old result is consumed", () async {
    final old = rig.plan("/sdk-output/unconsumed.mp4");
    final starting = rig.start(old);
    await old.dispatched.future;
    old.emit(_Finalize());
    await rig.bounded(starting);
    final next = rig.plan("/sdk-output/next.mp4");

    expect(await rig.bounded(rig.start(next)), isA<CameraException>());
    expect(next.dispatched.isCompleted, isFalse);
    final original = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(original, isA<XFile>());
    expect((original as XFile).path, old.path);

    await rig.startSuccessfully(next);
    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, next.path);
  });

  test("old late events cannot finalize or clear a later camera recorder", () async {
    final old = rig.plan("/sdk-output/old.mp4");
    await rig.startSuccessfully(old);
    expect(await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7))), isA<XFile>());
    final next = rig.plan("/sdk-output/new-camera.mp4", finalizeOnClose: false);
    await rig.startSuccessfully(next, cameraId: 8);
    final stopping = rig.watch(rig.camera.stopVideoRecording(8));
    await next.closed.future;

    old.emit(_Start());
    old.emit(_Finalize());
    expect(await rig.bounded(stopping), isA<_Pending>());
    expect(rig.camera.recording, same(next.recording));
    next.emit(_Finalize());

    final stopped = await rig.bounded(stopping);
    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, next.path);
    expect(next.closeCalls, 1);
  });

  test("stop for another camera cannot close the active recorder", () async {
    final attempt = rig.plan("/sdk-output/owned.mp4");
    await rig.startSuccessfully(attempt);

    expect(await rig.bounded(rig.watch(rig.camera.stopVideoRecording(99))), isA<CameraException>());
    expect(attempt.closeCalls, 0);
    expect(rig.camera.recording, same(attempt.recording));
    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));
    expect(stopped, isA<XFile>());
  });

  test("normal persistent recording closes explicitly and returns its path", () async {
    final attempt = rig.plan("/sdk-output/normal.mp4");
    await rig.startSuccessfully(attempt);

    final stopped = await rig.bounded(rig.watch(rig.camera.stopVideoRecording(7)));

    expect(stopped, isA<XFile>());
    expect((stopped as XFile).path, attempt.path);
    expect(attempt.persistentCalls, 1);
    expect(attempt.closeCalls, 1);
  });
}

class _Pending {}
class _Provider extends Mock implements ProcessCameraProvider {}
class _Preview extends Mock implements Preview {}
class _Analysis extends Mock implements ImageAnalysis {}
class _VideoCapture extends Mock implements VideoCapture {}
class _Recorder extends Mock implements Recorder {}
class _PendingRecording extends Mock implements PendingRecording {}
class _Recording extends Mock implements Recording {}
class _Orientation extends Mock implements DeviceOrientationManager {}

class _Listener extends VideoRecordEventListener {
  _Listener(void Function(VideoRecordEventListener, VideoRecordEvent) callback)
      : super.pigeon_detached(onEvent: callback);
}
class _Start extends VideoRecordEventStart {
  _Start() : super.pigeon_detached();
}
class _Finalize extends VideoRecordEventFinalize {
  _Finalize() : super.pigeon_detached();
}

class _NativeAttempt {
  _NativeAttempt(this.path, {required this.finalizeOnClose});
  final String path;
  final bool finalizeOnClose;
  final pending = _PendingRecording();
  final recording = _Recording();
  final handle = Completer<Recording>();
  final dispatched = Completer<void>();
  final closed = Completer<void>();
  VideoRecordEventListener? listener;
  int closeCalls = 0;
  int persistentCalls = 0;

  void returnHandle() {
    if (!handle.isCompleted) handle.complete(recording);
  }

  void emit(VideoRecordEvent event) {
    final target = listener;
    if (target != null) target.onEvent(target, event);
  }
}

class _Rig {
  _Rig() {
    PigeonOverrides.pigeon_reset();
    camera.processCameraProvider = provider;
    camera.preview = preview;
    camera.imageAnalysis = analysis;
    camera.videoCapture = capture;
    camera.recorder = recorder;
    camera.enableRecordingAudio = false;
    camera.captureOrientationLocked = true;
    when(() => provider.isBound(any())).thenAnswer((_) async => true);
    when(() => provider.unbind(any())).thenAnswer((_) async {});
    when(() => provider.unbindAll()).thenAnswer((_) async { hardwareUnbound = true; });
    when(() => preview.releaseSurfaceProvider()).thenAnswer((_) async {});
    when(() => analysis.clearAnalyzer()).thenAnswer((_) async {});
    when(() => orientation.stopListeningForDeviceOrientationChange()).thenAnswer((_) async {});
    PigeonOverrides.deviceOrientationManager_new = ({required onDeviceOrientationChanged}) => orientation;
    PigeonOverrides.videoRecordEventListener_new = ({required onEvent}) => _Listener(onEvent);
  }

  final camera = AndroidCameraCameraX();
  final provider = _Provider();
  final preview = _Preview();
  final analysis = _Analysis();
  final capture = _VideoCapture();
  final recorder = _Recorder();
  final orientation = _Orientation();
  final attempts = <_NativeAttempt>[];
  final operations = <Future<Object?>>[];
  bool hardwareUnbound = false;

  _NativeAttempt plan(String path, {bool delayHandle = false, bool finalizeOnClose = true}) {
    final attempt = _NativeAttempt(path, finalizeOnClose: finalizeOnClose);
    attempts.add(attempt);
    when(() => recorder.prepareRecording(path)).thenAnswer((_) async => attempt.pending);
    when(() => attempt.pending.asPersistentRecording()).thenAnswer((_) async {
      attempt.persistentCalls++;
      return attempt.pending;
    });
    when(() => attempt.pending.withAudioEnabled(true)).thenAnswer((_) async => attempt.pending);
    when(() => attempt.pending.start(any())).thenAnswer((invocation) {
      attempt.listener = invocation.positionalArguments.single as VideoRecordEventListener;
      if (!attempt.dispatched.isCompleted) attempt.dispatched.complete();
      return attempt.handle.future;
    });
    when(() => attempt.recording.close()).thenAnswer((_) async {
      attempt.closeCalls++;
      if (!attempt.closed.isCompleted) attempt.closed.complete();
      if (attempt.finalizeOnClose) scheduleMicrotask(() => attempt.emit(_Finalize()));
    });
    if (!delayHandle) attempt.returnHandle();
    return attempt;
  }

  Future<Object?> watch<T>(Future<T> operation) {
    final observed = operation.then<Object?>((value) => value, onError: (Object error) => error);
    operations.add(observed);
    return observed;
  }

  Future<Object?> bounded(Future<Object?> operation) => operation.timeout(
      const Duration(milliseconds: 300), onTimeout: () => _Pending());

  Future<Object?> start(_NativeAttempt attempt, {int cameraId = 7}) => watch(camera.startVideoCapturing(
      VideoCaptureOptions(cameraId, videoOutputPath: attempt.path)));

  Future<void> startSuccessfully(_NativeAttempt attempt, {int cameraId = 7}) async {
    final starting = start(attempt, cameraId: cameraId);
    await attempt.dispatched.future.timeout(const Duration(seconds: 1));
    attempt.emit(_Start());
    expect(await bounded(starting), isNull);
  }

  Future<void> settleTestDoubles() async {
    for (final attempt in attempts) { attempt.returnHandle(); }
    // Let unchanged legacy starts/stops finish even when their missing terminal
    // handling caused the assertion to fail. These are proxy events, not media.
    for (var i = 0; i < 3; i++) {
      for (final attempt in attempts) {
        attempt.emit(_Start());
        attempt.emit(_Finalize());
      }
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(operations).timeout(const Duration(seconds: 1), onTimeout: () => <Object?>[]);
  }
}
