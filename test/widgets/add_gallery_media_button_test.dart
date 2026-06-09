import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/widgets/add_gallery_media_button.dart";
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

  tearDownAll(() {
    testPathProvider.dispose();
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
  });

  testWidgets("button label fits narrow desktop panes", (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(220, 160));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 140,
            child: AddGalleryMediaButton(),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets("active session button opens media filter dialog",
      (tester) async {
    SessionManager.instance.startSession(
      "gallery-button-guid",
      "gallery-button-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();

    expect(find.text("Select Media Filters"), findsOneWidget);
    expect(find.text("Browse All"), findsOneWidget);
    expect(find.text("Apply"), findsOneWidget);
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  Directory get documentsDir {
    _documentsDir ??=
        Directory.systemTemp.createTempSync("add_gallery_button_docs");
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
