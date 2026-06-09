import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/screens/uploader_info_screen.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/uploader_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _UploaderInfoPathProvider pathProvider = _UploaderInfoPathProvider();
  late Directory tempDir;

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
    UploaderService().reset();
    tempDir = Directory.systemTemp.createTempSync("uploader_info_screen_test");
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    UploaderService().reset();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  testWidgets("cancel action clears the current upload row", (tester) async {
    SessionManager.instance.startSession(
      "uploader-info-session-guid",
      "uploader-info-session",
      deviceType: "Slave",
    );

    final videoFile = File("${tempDir.path}/current-upload.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    final video = CapturedVideo(
      videoPath: videoFile.path,
      slaveDeviceId: "uploader-info-device",
      startRecordingDate: DateTime(2026, 6, 8, 19, 40),
      endRecordingDate: DateTime(2026, 6, 8, 19, 40, 5),
      receivedDate: DateTime(2026, 6, 8, 19, 40, 6),
    );

    SessionManager.instance.currentSession?.addVideo(video);
    UploaderService().currentlyUploadingNotifier.value = video;

    await tester.pumpWidget(
      const MaterialApp(
        home: UploaderInfoScreen(),
      ),
    );
    await tester.pump();

    expect(find.byTooltip("Cancel upload"), findsOneWidget);

    await tester.tap(find.byTooltip("Cancel upload"));
    await tester.pump();

    expect(UploaderService().isUploading, isFalse);
    expect(UploaderService().currentlyUploadingNotifier.value, isNull);
  });
}

class _UploaderInfoPathProvider extends PathProviderPlatform {
  final Directory documentsDir =
      Directory.systemTemp.createTempSync("uploader_info_screen_docs");

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }

  void dispose() {
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  }
}
