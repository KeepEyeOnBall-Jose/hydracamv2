import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:mocktail/mocktail.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:hydracam/master/master_server.dart";
import "package:hydracam/models/sync_metadata.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/session_media_storage.dart";

import "../test_utils/mock_services.dart";

class MockWebSocket extends Mock implements WebSocket {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pathProvider = _MasterServerPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    pathProvider.resetDocumentsDir();
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    pathProvider.resetDocumentsDir();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  MasterServer buildServer(Directory storageRoot) {
    return MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "192.168.178.153",
          source: "master-test",
        ),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {},
        now: () => DateTime.fromMillisecondsSinceEpoch(1770000000789),
      ),
    );
  }

  SyncMetadata buildSyncMetadata() {
    return SyncMetadata(
      offsetMs: 42,
      minRoundTripMs: 8,
      uncertaintyMs: 3,
      confidence: TimeSyncConfidence.green,
      sampleCount: 6,
      calibratedAt: DateTime.utc(2026, 6, 9, 3, 40),
      calibrationAgeMs: 1200,
    );
  }

  test("incoming photo message carries syncMetadata into stored CapturedPhoto",
      () async {
    final storageRoot =
        Directory.systemTemp.createTempSync("master_media_sync_photo");
    final server = buildServer(storageRoot);
    SessionManager.instance.startSession(
      "sync-photo-guid",
      "sync-photo-id",
      deviceType: "Master",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "slave-a",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": DateTime.utc(2026, 6, 9, 3, 44).toIso8601String(),
          "syncMetadata": buildSyncMetadata().toJson(),
        }),
        socket: MockWebSocket(),
      );

      final photos =
          SessionManager.instance.currentSession?.capturedPhotos ?? [];
      expect(photos, hasLength(1));
      final syncMetadata = photos.single.syncMetadata;
      expect(syncMetadata, isNotNull);
      expect(syncMetadata!.offsetMs, 42);
      expect(syncMetadata.confidence, TimeSyncConfidence.green);
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });

  test("incoming video message carries syncMetadata into stored CapturedVideo",
      () async {
    final storageRoot =
        Directory.systemTemp.createTempSync("master_media_sync_video");
    final server = buildServer(storageRoot);
    SessionManager.instance.startSession(
      "sync-video-guid",
      "sync-video-id",
      deviceType: "Master",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "video",
          "deviceId": "slave-a",
          "data": [0x00, 0x00, 0x00, 0x18],
          "startRecordingDate":
              DateTime.utc(2026, 6, 9, 3, 44).toIso8601String(),
          "endRecordingDate": DateTime.utc(2026, 6, 9, 3, 45).toIso8601String(),
          "syncMetadata": buildSyncMetadata().toJson(),
        }),
        socket: MockWebSocket(),
      );

      final videos =
          SessionManager.instance.currentSession?.capturedVideos ?? [];
      expect(videos, hasLength(1));
      final syncMetadata = videos.single.syncMetadata;
      expect(syncMetadata, isNotNull);
      expect(syncMetadata!.offsetMs, 42);
      expect(syncMetadata.confidence, TimeSyncConfidence.green);
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });

  test("omitting syncMetadata leaves stored media syncMetadata null", () async {
    final storageRoot =
        Directory.systemTemp.createTempSync("master_media_sync_absent");
    final server = buildServer(storageRoot);
    SessionManager.instance.startSession(
      "sync-absent-guid",
      "sync-absent-id",
      deviceType: "Master",
    );

    try {
      await server.handleIncomingMessageForTest(
        jsonEncode({
          "type": "photo",
          "deviceId": "slave-a",
          "data": [0xFF, 0xD8, 0xFF],
          "captureDate": DateTime.utc(2026, 6, 9, 3, 44).toIso8601String(),
        }),
        socket: MockWebSocket(),
      );

      final photos =
          SessionManager.instance.currentSession?.capturedPhotos ?? [];
      expect(photos, hasLength(1));
      expect(photos.single.syncMetadata, isNull);
    } finally {
      storageRoot.deleteSync(recursive: true);
    }
  });
}

class _MasterServerPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??= Directory.systemTemp.createTempSync("master_server_docs");
    return _documentsDir!.path;
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
