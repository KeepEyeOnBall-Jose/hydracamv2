import "dart:async";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/gallery_persistence_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      "gallery_persistence_service_test",
    );
  });

  tearDown(() {
    GalleryPersistenceService.resetForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  File createPhoto() {
    final file = File("${tempDir.path}/capture.jpg");
    file.writeAsBytesSync(<int>[0xff, 0xd8, 0xff, 0xd9]);
    return file;
  }

  test("savePhoto returns when Photos permission request stalls", () async {
    final permissionCompleter = Completer<bool>();
    var attemptedGallerySave = false;

    GalleryPersistenceService.configureForTesting(
      operationTimeout: const Duration(milliseconds: 20),
      permissionRequester: () => permissionCompleter.future,
      photoSaver: (_, __) async {
        attemptedGallerySave = true;
      },
    );

    await GalleryPersistenceService.savePhoto(createPhoto().path);

    expect(attemptedGallerySave, isFalse);
  });

  test("savePhoto returns when gallery photo save stalls", () async {
    final saveCompleter = Completer<void>();

    GalleryPersistenceService.configureForTesting(
      operationTimeout: const Duration(milliseconds: 20),
      permissionRequester: () async => true,
      photoSaver: (_, __) => saveCompleter.future,
    );

    await GalleryPersistenceService.savePhoto(createPhoto().path);
  });
}
