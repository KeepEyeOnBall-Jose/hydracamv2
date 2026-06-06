import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/permission_service.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _TestPathProviderPlatform pathProvider = _TestPathProviderPlatform();

  setUpAll(() {
    PathProviderPlatform.instance = pathProvider;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() {
    pathProvider.dispose();
  });

  test("requestAllPermissions skips unsupported macOS permission handler",
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final bool granted = await PermissionService.requestAllPermissions();

    expect(granted, isTrue);
  });

  test("openAppSettings skips unsupported macOS permission handler", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await expectLater(PermissionService.openAppSettings(), completes);
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  Directory? _documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    _documentsDir ??= Directory.systemTemp.createTempSync("permission_docs");
    return _documentsDir!.path;
  }

  void dispose() {
    if (_documentsDir != null && _documentsDir!.existsSync()) {
      _documentsDir!.deleteSync(recursive: true);
    }
    _documentsDir = null;
  }
}
