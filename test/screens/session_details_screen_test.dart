import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/master/master_screen.dart";
import "package:hydracam/screens/session_details_screen.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/storage_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";
// ignore: depend_on_referenced_packages
import "package:video_player_platform_interface/video_player_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testPathProvider = _TestPathProviderPlatform();
  late VideoPlayerPlatform originalVideoPlayerPlatform;

  setUpAll(() {
    PathProviderPlatform.instance = testPathProvider;
    SharedPreferences.setMockInitialValues({});
    if (!CameraServiceSingleton.isInitialized) {
      final storageService = StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      );
      CameraServiceSingleton.initialize(
        storageService,
        useMockCamera: true,
      );
    }
    originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    testPathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
    testPathProvider.dispose();
  });

  testWidgets("session details shows player assignment backend state",
      (tester) async {
    final session = CaptureSession(
      sessionId: "session-players",
      sessionGuid: "guid-players",
      startTime: DateTime.utc(2026, 6, 8, 20, 55),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Players"), findsOneWidget);
    expect(find.text("Source: backend not configured"), findsOneWidget);
    expect(
      find.text("Import source: waiting for session-player API"),
      findsOneWidget,
    );
    expect(
      find.text("Mid-session additions unavailable until FR-061 exists"),
      findsOneWidget,
    );
    expect(find.text("Player assignment unavailable"), findsOneWidget);
  });

  testWidgets("session details title prefers the session guid", (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Session: backend-session-guid"), findsWidgets);
    expect(find.text("Session: legacy-session-id"), findsNothing);
  });

  testWidgets("session details metadata uses guid as primary session reference",
      (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Session: backend-session-guid"), findsNWidgets(2));
    expect(find.text("Session ID: legacy-session-id"), findsNothing);
    expect(find.text("Legacy Session ID: legacy-session-id"), findsOneWidget);
  });

  testWidgets("session details shows computed upload state", (tester) async {
    final session = CaptureSession(
      sessionId: "mixed-session-id",
      sessionGuid: "mixed-session-guid",
      startTime: DateTime.utc(2026, 6, 18, 10),
      capturedPhotos: [
        CapturedPhoto(
          photoPath: "uploaded.jpg",
          slaveDeviceId: "device-one",
          captureDate: DateTime.utc(2026, 6, 18, 10, 1),
          receivedDate: DateTime.utc(2026, 6, 18, 10, 1, 1),
          isUploaded: true,
        ),
      ],
      capturedVideos: [
        CapturedVideo(
          videoPath: "pending.mp4",
          slaveDeviceId: "device-one",
          startRecordingDate: DateTime.utc(2026, 6, 18, 10, 2),
          endRecordingDate: DateTime.utc(2026, 6, 18, 10, 2, 10),
          receivedDate: DateTime.utc(2026, 6, 18, 10, 2, 11),
          isUploaded: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Upload State: Partially uploaded"), findsOneWidget);
  });

  testWidgets("load session action falls back to session id without guid",
      (tester) async {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      startTime: DateTime.utc(2026, 6, 9),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    await tester.tap(find.byTooltip("Load Session"));
    await tester.pump();

    expect(
      find.textContaining("legacy-session-id"),
      findsWidgets,
    );
    expect(
      find.textContaining("Null check operator used on a null value"),
      findsNothing,
    );
  });

  testWidgets("load session action can restore through storage identifier",
      (tester) async {
    testPathProvider.writeSessionMetadata(
      storageIdentifier: "directory-reference-guid",
      sessionGuid: "backend-session-guid",
      sessionId: "legacy-session-id",
    );
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 18, 16),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(
          session: session,
          storageIdentifier: "directory-reference-guid",
        ),
      ),
    );

    await tester.tap(find.byTooltip("Load Session"));
    await _pumpUntilSessionGuid(tester, "backend-session-guid");

    expect(SessionManager.instance.sessionGuid, "backend-session-guid");
    expect(
        SessionManager.instance.currentSession?.sessionId, "legacy-session-id");
    expect(find.textContaining("Failed to load session:"), findsNothing);
  });

  testWidgets("upload confirm action reports missing restored metadata",
      (tester) async {
    final videoFile = File("${testPathProvider.documentsDir.path}/upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final session = CaptureSession(
      sessionId: "legacy-upload-id",
      sessionGuid: "missing-upload-guid",
      startTime: DateTime.utc(2026, 6, 9),
      capturedVideos: [
        CapturedVideo(
          videoPath: videoFile.path,
          slaveDeviceId: "upload-device",
          startRecordingDate: DateTime.utc(2026, 6, 9, 1),
          endRecordingDate: DateTime.utc(2026, 6, 9, 1, 1),
          receivedDate: DateTime.utc(2026, 6, 9, 1, 2),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    final uploadAction = find.byIcon(Icons.cloud_upload_outlined);
    await tester.ensureVisible(uploadAction);
    await tester.pumpAndSettle();
    await tester.tap(uploadAction);
    await tester.pumpAndSettle();

    expect(find.text("Upload Unsent Media"), findsOneWidget);

    await tester.tap(find.text("Confirm"));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("missing-upload-guid"),
      findsWidgets,
    );
    expect(
      find.textContaining("Null check operator used on a null value"),
      findsNothing,
    );
  });

  testWidgets("missing photo file is labeled and does not offer upload",
      (tester) async {
    final missingPhotoPath = "${testPathProvider.documentsDir.path}/gone.jpg";
    final session = CaptureSession(
      sessionId: "missing-photo-session",
      sessionGuid: "missing-photo-guid",
      startTime: DateTime.utc(2026, 6, 17, 18),
      capturedPhotos: [
        CapturedPhoto(
          photoPath: missingPhotoPath,
          slaveDeviceId: "old-phone",
          captureDate: DateTime.utc(2026, 6, 17, 18, 1),
          receivedDate: DateTime.utc(2026, 6, 17, 18, 2),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    expect(find.text("Local file missing"), findsOneWidget);

    final uploadAction = find.byIcon(Icons.cloud_upload_outlined);
    await tester.ensureVisible(uploadAction);
    await tester.pumpAndSettle();
    await tester.tap(uploadAction);
    await tester.pumpAndSettle();

    expect(find.text("Upload Unsent Media"), findsNothing);
    expect(find.text("Photo Not Found"), findsOneWidget);
  });

  testWidgets("tapping a session video opens the playback dialog",
      (tester) async {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    final videoFile = File("${testPathProvider.documentsDir.path}/saved.mp4")
      ..writeAsBytesSync([0, 0, 0, 16, 102, 116, 121, 112]);
    final session = CaptureSession(
      sessionId: "video-session",
      sessionGuid: "video-guid",
      startTime: DateTime.utc(2026, 6, 17),
      capturedVideos: [
        CapturedVideo(
          videoPath: videoFile.path,
          slaveDeviceId: "court-camera",
          startRecordingDate: DateTime.utc(2026, 6, 17, 10),
          endRecordingDate: DateTime.utc(2026, 6, 17, 10, 0, 10),
          receivedDate: DateTime.utc(2026, 6, 17, 10, 0, 11),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionDetailsScreen(session: session),
      ),
    );

    final videoTitle = find.text("Video from court-camera");
    await tester.ensureVisible(videoTitle);
    await tester.pumpAndSettle();
    await tester.tap(videoTitle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Video playback is not implemented yet."), findsNothing);
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(find.byIcon(Icons.videocam), findsOneWidget);
  });
}

Future<void> _pumpUntilSessionGuid(
  WidgetTester tester,
  String sessionGuid, {
  int maxPumps = 10,
}) async {
  for (var pumpCount = 0; pumpCount < maxPumps; pumpCount += 1) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    if (SessionManager.instance.sessionGuid == sessionGuid) {
      return;
    }
    await tester.pump();
  }
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync(
      "session_details_screen_docs",
    );
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void writeSessionMetadata({
    required String storageIdentifier,
    required String sessionGuid,
    required String sessionId,
  }) {
    final sessionDir =
        Directory("${documentsDir.path}/session_$storageIdentifier");
    sessionDir.createSync(recursive: true);
    File("${sessionDir.path}/metadata.json").writeAsStringSync(
      jsonEncode({
        "sessionId": sessionId,
        "sessionGuid": sessionGuid,
        "startTime": DateTime.utc(2026, 6, 18, 16).toIso8601String(),
        "endTime": DateTime.utc(2026, 6, 18, 17).toIso8601String(),
        "deviceType": "Master",
        "photos": [],
        "videos": [],
      }),
    );
  }

  void resetDocumentsDir() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }

  void dispose() {
    resetDocumentsDir();
  }
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _eventControllers = {};
  int _nextTextureId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final textureId = _nextTextureId++;
    final controller = StreamController<VideoEvent>.broadcast();
    _eventControllers[textureId] = controller;
    scheduleMicrotask(() {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(640, 360),
        ),
      );
    });
    return textureId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _eventControllers[textureId]?.stream ?? const Stream.empty();
  }

  @override
  Future<void> play(int textureId) async {}

  @override
  Future<void> pause(int textureId) async {}

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {}

  @override
  Future<Duration> getPosition(int textureId) async => Duration.zero;

  @override
  Widget buildView(int textureId) {
    return const ColoredBox(
      color: Colors.black,
      child: Icon(Icons.videocam, color: Colors.white),
    );
  }

  @override
  Future<void> dispose(int textureId) async {
    await _eventControllers.remove(textureId)?.close();
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
