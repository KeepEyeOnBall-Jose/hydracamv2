import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/gallery_session_candidate_source.dart";
import "package:hydracam/services/session_manager.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testPathProvider = _TestPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = testPathProvider;
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
  });

  setUp(() async {
    final docs = testPathProvider.documentsDir;
    if (docs.existsSync()) {
      docs.deleteSync(recursive: true);
    }
    docs.createSync(recursive: true);
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
  });

  tearDownAll(() {
    testPathProvider.dispose();
  });

  Future<void> writeSessionMetadata({
    required String sessionGuid,
    required String sessionId,
    required DateTime start,
    required DateTime end,
  }) async {
    final sessionDir =
        Directory("${testPathProvider.documentsDir.path}/session_$sessionGuid");
    sessionDir.createSync(recursive: true);
    await File("${sessionDir.path}/metadata.json").writeAsString(
      jsonEncode({
        "sessionId": sessionId,
        "sessionGuid": sessionGuid,
        "startTime": start.toIso8601String(),
        "endTime": end.toIso8601String(),
        "deviceType": "Master",
        "photos": [],
        "videos": [],
      }),
    );
  }

  test("loads active and historical gallery candidate sessions once", () async {
    SessionManager.instance.startSession(
      "active-guid",
      "active-id",
      deviceType: "Master",
    );
    await writeSessionMetadata(
      sessionGuid: "active-guid",
      sessionId: "active-id-from-disk",
      start: DateTime.utc(2026, 6, 8, 10),
      end: DateTime.utc(2026, 6, 8, 10, 30),
    );
    await writeSessionMetadata(
      sessionGuid: "old-guid",
      sessionId: "old-id",
      start: DateTime.utc(2026, 6, 8, 9),
      end: DateTime.utc(2026, 6, 8, 9, 30),
    );

    final candidates = await const GallerySessionCandidateSource().load();

    expect(
      candidates.map((session) => session.sessionGuid),
      ["active-guid", "old-guid"],
    );
    expect(candidates.first.sessionId, "active-id");
    expect(SessionManager.instance.sessionGuid, "active-guid");
    expect(SessionManager.instance.deviceType, "Master");
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??= Directory.systemTemp.createTempSync(
      "gallery_session_candidate_source_docs",
    );
    return _documentsDir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
