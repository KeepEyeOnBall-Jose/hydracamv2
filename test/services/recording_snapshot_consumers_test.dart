import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/master/master_announcer.dart";
import "package:hydracam/master/master_screen_controller.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/recorded_video_snapshots.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:hydracam/slave/slave_client.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

class _Announcer extends Mock implements MasterAnnouncer {}

// SDK paths are opaque return values. These tests create only JSON metadata,
// never media payloads, and make no camera/playable-video claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionGuid = "original-capture-session";
  final started = DateTime.utc(2026, 10, 25, 10);
  final stopped = started.add(const Duration(seconds: 10));
  final later = stopped.add(const Duration(minutes: 1));
  final originalProvider = PathProviderPlatform.instance;
  late Directory directory;
  late _Documents documents;
  late MockCameraService camera;
  late RecordedVideoSnapshot snapshot;
  late ValueNotifier<bool> interrupted;

  MediaCaptureContext context(String cameraName) => MediaCaptureContext(
        perspective: CameraPerspectiveMetadata.unknown,
        level: DeviceLevelMetadata.unavailable(capturedAt: started),
        cameraName: cameraName,
        cameraLensDirection: "back",
        cameraSensorOrientation: 90,
        videoCaptureProfile: "detail4k30",
        deviceId: "consumer-device",
      );

  setUpAll(() {
    registerFallbackValue(CapturedVideo(
      videoData: null,
      videoPath: "/sdk-output/unused.mp4",
      slaveDeviceId: "consumer-device",
      startRecordingDate: started,
      endRecordingDate: stopped,
      receivedDate: stopped,
    ));
    registerFallbackValue(RecordedVideoSnapshot.capture(
      captureId: "unused-capture",
      path: "/sdk-output/unused.mp4",
      startedAt: started,
      stoppedAt: stopped,
      context: null,
    ));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "device_id": "consumer-device",
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    directory =
        Directory.systemTemp.createTempSync("capture_consumer_metadata_");
    documents = _Documents(directory);
    PathProviderPlatform.instance = documents;
    camera = MockCameraService();
    interrupted = ValueNotifier(false);
    snapshot = RecordedVideoSnapshot.capture(
      captureId: "original-capture",
      path: "${directory.path}/sdk-returned.mp4",
      startedAt: started,
      stoppedAt: stopped,
      context: context("0"),
      sessionGuid: sessionGuid,
    );
    when(() => camera.stopRecordingVideo())
        .thenAnswer((_) async => snapshot.path);
    when(() => camera.snapshotForRecordedVideo(snapshot.path))
        .thenAnswer((_) async => snapshot);
    when(() => camera.acknowledgeRecordedVideo(any())).thenAnswer((_) async {});
    when(() => camera.recordingInterrupted).thenReturn(interrupted);
    // Poison the mutable globals as if a later recording had already started.
    when(() => camera.videoStartRecordingDate).thenReturn(later);
    when(() => camera.videoEndRecordingDate)
        .thenReturn(later.add(const Duration(seconds: 20)));
    when(() => camera.recordingCaptureContext).thenReturn(context("1"));
  });

  tearDown(() async {
    documents.release();
    UploaderService().reset();
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    interrupted.dispose();
    PathProviderPlatform.instance = originalProvider;
    directory.deleteSync(recursive: true);
  });

  MasterScreenController master(MockSessionManager sessions) {
    final server = MockMasterServer();
    when(() => server.cameraService).thenReturn(camera);
    when(() => server.stopServer()).thenReturn(null);
    final announcer = _Announcer();
    when(() => announcer.stopBroadcasting()).thenReturn(null);
    return MasterScreenController(
        masterServer: server, announcer: announcer, sessionManager: sessions);
  }

  test(
      "master saves the returned path snapshot and acknowledges only after save",
      () async {
    final sessions = MockSessionManager();
    when(() => sessions.sessionGuid).thenReturn(sessionGuid);
    final saving = Completer<void>();
    final saved = Completer<void>();
    CapturedVideo? captured;
    when(() => sessions.addVideo(any())).thenAnswer((invocation) async {
      captured = invocation.positionalArguments.single as CapturedVideo;
      saving.complete();
      await saved.future;
    });
    final controller = master(sessions);
    addTearDown(controller.dispose);
    final stopping = controller.stopMasterRecordingVideo();
    try {
      await saving.future.timeout(const Duration(seconds: 1));
      verify(() => camera.snapshotForRecordedVideo(snapshot.path)).called(1);
      verifyNever(() => camera.acknowledgeRecordedVideo(any()));
    } finally {
      saved.complete();
    }
    final video = await stopping;
    expect(video, same(captured));
    expect(video.startRecordingDate, started);
    expect(video.endRecordingDate, stopped);
    expect(video.captureContext?.cameraName, "0");
    verify(() => camera.acknowledgeRecordedVideo(snapshot)).called(1);
  });

  test("master retains recovery metadata when the durable save fails",
      () async {
    final sessions = MockSessionManager();
    when(() => sessions.sessionGuid).thenReturn(sessionGuid);
    when(() => sessions.addVideo(any())).thenThrow(StateError("save rejected"));
    final controller = master(sessions);
    addTearDown(controller.dispose);
    await expectLater(controller.stopMasterRecordingVideo(), throwsStateError);
    verifyNever(() => camera.acknowledgeRecordedVideo(any()));
  });

  for (final activeSession in <String?>["later-session", null]) {
    test("master cannot attach an old capture to session $activeSession",
        () async {
      final sessions = MockSessionManager();
      when(() => sessions.sessionGuid).thenReturn(activeSession);
      when(() => sessions.addVideo(any())).thenAnswer((_) async {});
      final controller = master(sessions);
      addTearDown(controller.dispose);
      await expectLater(
          controller.stopMasterRecordingVideo(), throwsStateError);
      verifyNever(() => sessions.addVideo(any()));
      verifyNever(() => camera.acknowledgeRecordedVideo(any()));
    });
  }

  test("slave saves the returned path snapshot and acknowledges after metadata",
      () async {
    SessionManager.instance
        .joinSession(sessionGuid, sessionGuid, deviceType: "Slave");
    await SessionManager.instance.updateMetadata();
    final client = SlaveClient("ws://unused", cameraService: camera)
      ..isRecordingVideo = true
      ..videoStartRecordingDate = later;
    addTearDown(client.disconnect);
    documents.hold();
    final stopping = client.stopRecordingLocally();
    try {
      await documents.requested.future.timeout(const Duration(seconds: 1));
      verify(() => camera.snapshotForRecordedVideo(snapshot.path)).called(1);
      verifyNever(() => camera.acknowledgeRecordedVideo(any()));
    } finally {
      documents.release();
    }
    await stopping;
    final video = SessionManager.instance.currentSession!.capturedVideos.single;
    expect(video.startRecordingDate, started);
    expect(video.endRecordingDate, stopped);
    expect(video.captureContext?.cameraName, "0");
    verify(() => camera.acknowledgeRecordedVideo(snapshot)).called(1);
  });

  for (final activeSession in <String?>["later-session", null]) {
    test("slave cannot attach an old capture to session $activeSession",
        () async {
      if (activeSession != null) {
        SessionManager.instance
            .joinSession(activeSession, activeSession, deviceType: "Slave");
        await SessionManager.instance.updateMetadata();
      }
      final client = SlaveClient("ws://unused", cameraService: camera)
        ..isRecordingVideo = true
        ..videoStartRecordingDate = later;
      addTearDown(client.disconnect);
      await client.stopRecordingLocally();
      expect(SessionManager.instance.currentSession?.capturedVideos ?? [],
          isEmpty);
      verifyNever(() => camera.acknowledgeRecordedVideo(any()));
      verify(() => camera.snapshotForRecordedVideo(snapshot.path)).called(1);
    });
  }
}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final Directory directory;
  Completer<String?>? _held;
  Completer<void> requested = Completer<void>();

  void hold() {
    requested = Completer<void>();
    _held = Completer<String?>();
  }

  void release() {
    final held = _held;
    _held = null;
    if (held != null && !held.isCompleted) held.complete(directory.path);
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final held = _held;
    if (held == null) return directory.path;
    if (!requested.isCompleted) requested.complete();
    return held.future;
  }
}
