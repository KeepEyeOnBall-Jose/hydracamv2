import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionManager sessionManager;
  late UploaderService uploaderService;
  late Directory tempMediaDir;
  late _DeterministicPathProvider pathProvider;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "masterShouldRecord": true,
    });
  });

  setUp(() async {
    pathProvider = _DeterministicPathProvider();
    PathProviderPlatform.instance = pathProvider;

    sessionManager = SessionManager.instance;
    uploaderService = UploaderService();
    await _resetSessionState(sessionManager, uploaderService);

    tempMediaDir =
        Directory.systemTemp.createTempSync("hydracam_multi_device_media");
  });

  tearDown(() async {
    await _resetSessionState(sessionManager, uploaderService);

    if (tempMediaDir.existsSync()) {
      tempMediaDir.deleteSync(recursive: true);
    }

    pathProvider.dispose();
  });

  group("Photo Scenarios", () {
    test("Scenario P1: single slave burst populates queue and metadata",
        () async {
      const sessionGuid = "session_p1";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      for (int i = 0; i < 3; i++) {
        sessionManager.addPhoto(_createPhoto(tempMediaDir,
            deviceId: "slave-alpha", fileName: "p1-$i.jpg"));
      }

      await _flushAsyncTasks();

      expect(sessionManager.currentSession?.capturedPhotos.length, 3);
      expect(sessionManager.currentSession?.capturedPhotos.first.slaveDeviceId,
          "slave-alpha");
      expect(uploaderService.queueLength, 3);

      final metadata = await _readMetadata(pathProvider, sessionGuid);
      expect((metadata["photos"] as List).length, 3);
    });

    test("Scenario P2: two slaves contribute photos with unique device IDs",
        () async {
      const sessionGuid = "session_p2";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      sessionManager.addPhoto(_createPhoto(tempMediaDir,
          deviceId: "slave-one", fileName: "p2-a.jpg"));
      sessionManager.addPhoto(_createPhoto(tempMediaDir,
          deviceId: "slave-two", fileName: "p2-b.jpg"));

      await _flushAsyncTasks();

      final photos = sessionManager.currentSession?.capturedPhotos;
      expect(photos?.length, 2);
      expect(photos?.map((p) => p.slaveDeviceId).toSet(),
          equals({"slave-one", "slave-two"}));

      final metadata = await _readMetadata(pathProvider, sessionGuid);
      final storedDeviceIds = (metadata["photos"] as List)
          .map((entry) => entry["slaveDeviceId"] as String)
          .toSet();
      expect(storedDeviceIds, equals({"slave-one", "slave-two"}));
    });

    test("Scenario P3: round-robin commands respect device order", () async {
      const sessionGuid = "session_p3";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      final deviceOrder = ["slave-A", "slave-B", "slave-C", "slave-D"];
      for (final deviceId in deviceOrder) {
        sessionManager.addPhoto(_createPhoto(tempMediaDir,
            deviceId: deviceId, fileName: "$deviceId.jpg"));
      }

      await _flushAsyncTasks();

      final photos = sessionManager.currentSession?.capturedPhotos;
      expect(photos?.length, deviceOrder.length);
      expect(photos?.map((p) => p.slaveDeviceId).toList(), equals(deviceOrder));
      expect(uploaderService.queueLength, deviceOrder.length);
    });

    test("Scenario P4: master rotation resets session state", () async {
      sessionManager.startSession("session_p4_a", null, deviceType: "Master");
      sessionManager.addPhoto(
          _createPhoto(tempMediaDir, deviceId: "slave-A", fileName: "p4.jpg"));
      await _flushAsyncTasks();
      expect(uploaderService.queueLength, 1);

      await sessionManager.endSession();
      uploaderService.reset();

      sessionManager.startSession("session_p4_b", null, deviceType: "Master");
      expect(sessionManager.sessionGuid, "session_p4_b");
      expect(sessionManager.currentSession?.capturedPhotos, isEmpty);
      expect(uploaderService.queueLength, 0);
    });
  });

  group("Video Scenarios", () {
    test("Scenario V1: single slave video stored in session", () async {
      const sessionGuid = "session_v1";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-alpha",
          fileName: "v1.mp4",
          duration: const Duration(seconds: 5)));

      await _flushAsyncTasks();

      expect(sessionManager.currentSession?.capturedVideos.length, 1);
      expect(uploaderService.queueLength, 1);
    });

    test("Scenario V2: multiple slave videos persist metadata", () async {
      const sessionGuid = "session_v2";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-one",
          fileName: "v2-a.mp4",
          duration: const Duration(seconds: 12)));
      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-two",
          fileName: "v2-b.mp4",
          duration: const Duration(seconds: 18)));

      await _flushAsyncTasks();

      final metadata = await _readMetadata(pathProvider, sessionGuid);
      expect((metadata["videos"] as List).length, 2);
      expect(uploaderService.queueLength, 2);
    });

    test("Scenario V3: scheduled starts preserve offsets", () async {
      const sessionGuid = "session_v3";
      sessionManager.startSession(sessionGuid, null, deviceType: "Master");

      final start = DateTime.now();
      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-one",
          fileName: "v3-a.mp4",
          startTime: start,
          duration: const Duration(seconds: 10)));
      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-two",
          fileName: "v3-b.mp4",
          startTime: start.add(const Duration(seconds: 2)),
          duration: const Duration(seconds: 10)));
      sessionManager.addVideo(_createVideo(tempMediaDir,
          deviceId: "slave-three",
          fileName: "v3-c.mp4",
          startTime: start.add(const Duration(seconds: 4)),
          duration: const Duration(seconds: 10)));

      await _flushAsyncTasks();

      final videos = sessionManager.currentSession?.capturedVideos;
      expect(videos?.length, 3);
      final offsets = videos
          ?.map((video) => video.startRecordingDate.difference(start).inSeconds)
          .toList();
      expect(offsets, equals([0, 2, 4]));
    });
  });
}

Future<void> _resetSessionState(
    SessionManager sessionManager, UploaderService uploaderService) async {
  uploaderService.reset();
  if (sessionManager.isSessionActive) {
    await sessionManager.endSession();
  }
}

CapturedPhoto _createPhoto(Directory mediaDir,
    {required String deviceId, required String fileName}) {
  final path = _writeMediaFile(mediaDir, fileName);
  final now = DateTime.now();
  return CapturedPhoto(
    photoPath: path,
    slaveDeviceId: deviceId,
    captureDate: now,
    receivedDate: now,
  );
}

CapturedVideo _createVideo(Directory mediaDir,
    {required String deviceId,
    required String fileName,
    Duration duration = Duration.zero,
    DateTime? startTime}) {
  final path = _writeMediaFile(mediaDir, fileName, sizeBytes: 2048);
  final start = startTime ?? DateTime.now();
  final end = start.add(duration);
  return CapturedVideo(
    videoPath: path,
    slaveDeviceId: deviceId,
    startRecordingDate: start,
    endRecordingDate: end,
    receivedDate: end,
  );
}

String _writeMediaFile(Directory dir, String fileName, {int sizeBytes = 1024}) {
  final file = File("${dir.path}/$fileName");
  file.createSync(recursive: true);
  file.writeAsBytesSync(List<int>.filled(sizeBytes, 12));
  return file.path;
}

Future<Map<String, dynamic>> _readMetadata(
    _DeterministicPathProvider provider, String sessionGuid) async {
  final metadataFile =
      File("${provider.documentsDir.path}/session_$sessionGuid/metadata.json");
  expect(metadataFile.existsSync(), isTrue,
      reason: "metadata file should exist for $sessionGuid");
  return jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
}

Future<void> _flushAsyncTasks() async {
  // Allow async `updateMetadata` and uploader queue scheduling to finish.
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

class _DeterministicPathProvider extends PathProviderPlatform {
  _DeterministicPathProvider()
      : documentsDir =
            Directory.systemTemp.createTempSync("hydracam_multi_device_docs");

  final Directory documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsDir.path;

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}
