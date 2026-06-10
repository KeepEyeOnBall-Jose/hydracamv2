import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/master/master_server.dart";
import "package:hydracam/services/camera_service_singleton.dart";
import "package:hydracam/services/network_info_service.dart";
import "package:hydracam/services/scheduled_task_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/session_media_storage.dart";
import "package:hydracam/services/storage_service.dart";
import "package:hydracam/services/time_sync_service.dart";
import "package:hydracam/slave/slave_client.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../test_utils/mock_services.dart";

/// End-to-end software evidence for the clock-sync feature.
///
/// This exercises the REAL code paths with no networking fakes for the sync
/// math: a real [MasterServer] binds a loopback socket, a real [SlaveClient]
/// connects over a WebSocket, the slave fires its `timeSyncRequest` bursts and
/// the master answers them, and [TimeSyncService] calibrates. We then drive a
/// real `takePhoto` command from the master so the slave constructs a
/// `CapturedPhoto` carrying `syncMetadata`, and assert on the real artifacts the
/// [SessionManager] persists: `metadata.json` plus the `<media>.sync.json`
/// sidecar.
///
/// Physical two-device camera capture cannot run in this environment; that part
/// is delivered as the operator runbook
/// (`docs/control/time-sync-two-device-runbook.md`). This test is the
/// reproducible software-level evidence that the path between calibration and
/// persisted sync metadata works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pathProvider = _IntegrationPathProvider();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      "device_id": "slave-integration",
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    if (!CameraServiceSingleton.isInitialized) {
      final storageService = StorageService(
        messengerState: null,
        lowStorageThreshold: 1.5,
        criticalStorageThreshold: 0.5,
        onCriticalStorageCallback: () async {},
      );
      CameraServiceSingleton.initialize(storageService, useMockCamera: true);
    }
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    TimeSyncService.instance.reset();
    pathProvider.reset();
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    TimeSyncService.instance.reset();
    pathProvider.reset();
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test(
      "real MasterServer + real SlaveClient calibrate and persist syncMetadata "
      "through a master-driven takePhoto", () async {
    final storageRoot =
        Directory.systemTemp.createTempSync("two_device_sync_storage");
    final scheduledTaskService = ScheduledTaskService();

    // Captured from the injected binder so the test learns the ephemeral port
    // the real MasterServer actually bound (MasterServer keeps it private).
    HttpServer? boundServer;

    // Real MasterServer, bound to a loopback ephemeral port so the test can run
    // anywhere. The only injected behavior is the network snapshot (so the
    // master does not probe the real Wi-Fi) and the media storage root.
    final master = MasterServer(
      MockCameraService(),
      masterNetworkSnapshotCache: MasterNetworkSnapshotCache(
        loadSnapshot: () async => const NetworkSnapshot(
          isWifiActive: true,
          ipAddress: "127.0.0.1",
          source: "integration-test",
        ),
      ),
      sessionMediaStorage: SessionMediaStorage(
        documentsDirectoryProvider: () async => storageRoot,
        galleryMediaPersistor: (filePath, mediaType) async {},
      ),
      bindMasterSocket: ({
        Object address = "0.0.0.0",
        int port = 4040,
      }) async {
        boundServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        return boundServer!;
      },
    );

    SlaveClient? slave;
    final calibrated = Completer<TimeSyncResult>();
    void calibrationListener() {
      final value = TimeSyncService.instance.latest.value;
      if (value != null && !calibrated.isCompleted) {
        calibrated.complete(value);
      }
    }

    TimeSyncService.instance.latest.addListener(calibrationListener);

    try {
      await master.startServer();
      final server = boundServer;
      expect(server, isNotNull,
          reason: "Injected binder should have bound a loopback socket.");
      final port = server!.port;

      // A backend-style session must be active on the slave's SessionManager so
      // the capture writes metadata.json and the sync sidecar.
      SessionManager.instance.startSession(
        "integration-sync-session",
        "integration-sync-id",
        deviceType: "Slave",
      );

      slave = SlaveClient(
        "ws://127.0.0.1:$port/ws",
        networkPayloadLoader: () async => null,
        scheduledTaskService: scheduledTaskService,
      );
      await slave.connect();

      // --- 1. Real calibration through the SlaveClient -> MasterServer path ---
      final result = await calibrated.future.timeout(
        const Duration(seconds: 5),
      );
      expect(result.sampleCount, greaterThan(0),
          reason: "Calibration should keep at least one usable sample.");
      // Both ends share this machine's clock, so the offset is tiny.
      expect(result.offset.inMilliseconds.abs(), lessThan(2000),
          reason: "Loopback offset should be near zero.");
      // The measured offset is applied to the scheduling clock.
      expect(scheduledTaskService.clockOffset, result.offset);

      // --- 2. Drive a real takePhoto command from the master ---
      // Register the slave on the master so it is a command-eligible client,
      // then send the real command over the wire.
      await _waitFor(
        () => master.getConnectedDeviceIds().contains("slave-integration"),
        timeout: const Duration(seconds: 3),
        description: "slave to register with master",
      );
      master.sendCommand("takePhoto", deviceId: "slave-integration");

      // --- 3. Assert on the persisted artifacts ---
      final documentsDir = await pathProvider.documentsDir();
      final metadataFile = File(
        "${documentsDir.path}/session_integration-sync-session/metadata.json",
      );
      await _waitFor(
        () => metadataFile.existsSync(),
        timeout: const Duration(seconds: 5),
        description: "metadata.json to be written",
      );

      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      final photos = (metadata["photos"] as List<dynamic>);
      await _waitFor(
        () {
          if (!metadataFile.existsSync()) return false;
          final current = jsonDecode(metadataFile.readAsStringSync())
              as Map<String, dynamic>;
          final list = current["photos"] as List<dynamic>? ?? const [];
          return list.isNotEmpty &&
              (list.first as Map<String, dynamic>)["syncMetadata"] != null;
        },
        timeout: const Duration(seconds: 5),
        description: "photo entry with syncMetadata",
      );

      final finalMetadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      final photoEntries = finalMetadata["photos"] as List<dynamic>;
      expect(photoEntries, isNotEmpty,
          reason: "Capture should append a photo to metadata.json.");
      final photoEntry = photoEntries.first as Map<String, dynamic>;
      final syncBlock = photoEntry["syncMetadata"] as Map<String, dynamic>?;
      expect(syncBlock, isNotNull,
          reason: "Persisted photo must carry syncMetadata.");
      for (final field in const [
        "offsetMs",
        "uncertaintyMs",
        "confidence",
        "sampleCount",
        "calibrationAgeMs",
      ]) {
        expect(syncBlock!.containsKey(field), isTrue,
            reason: "metadata syncMetadata missing $field");
      }

      // The sidecar lives next to the captured media file.
      final mediaPath = photoEntry["photoPath"].toString();
      final sidecarFile = File("$mediaPath.sync.json");
      await _waitFor(
        () => sidecarFile.existsSync(),
        timeout: const Duration(seconds: 5),
        description: "media sync sidecar to be written",
      );
      final sidecar =
          jsonDecode(await sidecarFile.readAsString()) as Map<String, dynamic>;
      final sidecarSync = sidecar["sync"] as Map<String, dynamic>?;
      expect(sidecarSync, isNotNull,
          reason: "Sidecar must contain a sync block.");
      for (final field in const [
        "offsetMs",
        "uncertaintyMs",
        "confidence",
        "sampleCount",
        "calibrationAgeMs",
      ]) {
        expect(sidecarSync!.containsKey(field), isTrue,
            reason: "sidecar sync missing $field");
      }
      // The sidecar and metadata.json describe the same calibration.
      expect(sidecarSync!["offsetMs"], syncBlock!["offsetMs"]);

      // Avoid an unused-local lint while documenting the early read above.
      expect(photos, isA<List<dynamic>>());

      // --- 4. Export the real artifacts so the evidence pack can copy them ---
      final exportDir = Platform.environment["SYNC_EVIDENCE_DIR"];
      if (exportDir != null && exportDir.isNotEmpty) {
        final target = Directory(exportDir)..createSync(recursive: true);
        File("${target.path}/sample-metadata.json").writeAsStringSync(
          const JsonEncoder.withIndent("  ").convert(finalMetadata),
          flush: true,
        );
        File("${target.path}/sample-media.sync.json").writeAsStringSync(
          const JsonEncoder.withIndent("  ").convert(sidecar),
          flush: true,
        );
      }
    } finally {
      TimeSyncService.instance.latest.removeListener(calibrationListener);
      slave?.disconnect();
      master.stopServer();
      if (storageRoot.existsSync()) {
        storageRoot.deleteSync(recursive: true);
      }
    }
  });
}

class _IntegrationPathProvider extends PathProviderPlatform {
  Directory? _documentsDir;

  Future<Directory> documentsDir() async {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("two_device_sync_docs");
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return (await documentsDir()).path;
  }

  void reset() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }

  void dispose() {
    reset();
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail("Timed out waiting for $description.");
}
