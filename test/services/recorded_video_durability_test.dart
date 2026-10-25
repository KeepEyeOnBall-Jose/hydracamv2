import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_context_metadata.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/camera_service.dart";
import "package:hydracam/services/recorded_video_snapshots.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

// These tests write actual local metadata/receipts, never media payloads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalProvider = PathProviderPlatform.instance;
  final sessions = SessionManager.instance;
  final started = DateTime.utc(2026, 10, 25, 10);
  final stopped = started.add(const Duration(seconds: 10));
  late Directory directory;
  late RecordedVideoSnapshots receipts;
  late CameraService camera;
  late RecordedVideoSnapshot snapshot;

  CapturedVideo video({String? path, MediaCaptureContext? context}) =>
      CapturedVideo(
        videoPath: path ?? snapshot.path,
        slaveDeviceId: "durability-device",
        startRecordingDate: started,
        endRecordingDate: stopped,
        receivedDate: stopped,
        captureContext: context,
        fileSizeInBytes: 0,
      );

  File receipt() => File("${directory.path}/recovery/original-capture.json");
  File metadata(String session) =>
      File("${directory.path}/session_$session/metadata.json");

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "device_id": "durability-device",
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    directory = await Directory.systemTemp.createTemp("recording-durability-");
    PathProviderPlatform.instance = _Documents(directory);
    receipts = RecordedVideoSnapshots(
        directory: () async => Directory("${directory.path}/recovery"));
    camera = CameraService(
        storageService: MockStorageService(), recordedVideoSnapshots: receipts);
    snapshot = RecordedVideoSnapshot.capture(
        captureId: "original-capture",
        path: "${directory.path}/opaque-sdk-return.mp4",
        startedAt: started,
        stoppedAt: stopped,
        context: null,
        sessionGuid: "original-session");
    await receipts.remember(snapshot);
    sessions.startSession("original-session", "original", deviceType: "Master");
  });

  tearDown(() async {
    UploaderService().reset();
    await sessions.endSession();
    PathProviderPlatform.instance = originalProvider;
    await directory.delete(recursive: true);
  });

  test("failed metadata write and RAM queue cannot acknowledge recovery",
      () async {
    // A directory at the file path causes a genuine filesystem write failure.
    await Directory(metadata("original-session").path).create(recursive: true);
    await sessions.addVideo(video());
    expect(UploaderService().queueLength, 1);
    expect(sessions.currentSession!.capturedVideos, hasLength(1));
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
    final pending = jsonDecode(await receipt().readAsString());
    expect(pending["sessionGuid"], "original-session");
    expect(pending["mediaPersisted"], isFalse);
    expect(pending["path"], snapshot.path);
  });

  test("another session's persisted matching clip cannot acknowledge original",
      () async {
    await sessions.endSession();
    sessions.startSession("another-session", "another", deviceType: "Master");
    await sessions.addVideo(video());
    expect(await metadata("another-session").exists(), isTrue);
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
    expect(sessions.sessionGuid, "another-session");
  });

  test("persisted different clip cannot acknowledge original", () async {
    await sessions.addVideo(video(path: "different-sdk-return.mp4"));
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
  });

  test("persisted different capture context cannot acknowledge original",
      () async {
    await sessions.addVideo(video(
        context: MediaCaptureContext.fromJson({"cameraName": "other-camera"})));
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
  });

  test("missing stored session identity is never repaired into an ACK",
      () async {
    await sessions.addVideo(video());
    final file = metadata("original-session");
    final disk = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    disk.remove("sessionGuid");
    final unchanged = jsonEncode(disk);
    await file.writeAsString(unchanged, flush: true);
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
    expect(await file.readAsString(), unchanged);
  });

  test("different persisted recording times cannot acknowledge original",
      () async {
    await sessions.addVideo(video());
    final file = metadata("original-session");
    final disk = jsonDecode(await file.readAsString());
    disk["videos"].single["endRecordingDate"] =
        stopped.add(const Duration(seconds: 1)).toIso8601String();
    await file.writeAsString(jsonEncode(disk), flush: true);
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isTrue);
  });

  test("exact original session clip read back from disk acknowledges receipt",
      () async {
    await sessions.addVideo(video());
    final disk = jsonDecode(await metadata("original-session").readAsString());
    expect(disk["videos"].single["videoPath"], snapshot.path);
    await camera.acknowledgeRecordedVideo(snapshot);
    expect(await receipt().exists(), isFalse);
    expect(
        (await receipts.forPath(snapshot.path))!.captureId, snapshot.captureId);
  });
}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}
