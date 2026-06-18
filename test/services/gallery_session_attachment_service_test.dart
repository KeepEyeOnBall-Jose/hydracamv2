import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/services/gallery_session_attachment_service.dart";
import "package:photo_manager/photo_manager.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _TestPathProviderPlatform pathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      "gallery_session_attachment_service_test",
    );
    pathProvider = _TestPathProviderPlatform(tempDir);
    PathProviderPlatform.instance = pathProvider;
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
    });
  });

  tearDown(() async {
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test("copyImportedMedia writes gallery files inside the session directory",
      () async {
    final sourceFile = File("${tempDir.path}/camera roll/photo one.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );

    final copiedFile = await service.copyImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "session-guid",
      assetId: "asset/id:one",
    );

    expect(copiedFile.path, isNot(sourceFile.path));
    expect(
      copiedFile.path,
      "${tempDir.path}/session_session-guid/gallery_asset_id_one_photo one.jpg",
    );
    expect(copiedFile.readAsBytesSync(), sourceFile.readAsBytesSync());
    expect(sourceFile.existsSync(), isTrue);
  });

  test("copyImportedMedia does not overwrite an existing session copy",
      () async {
    final sourceFile = File("${tempDir.path}/camera roll/idempotent.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0x05, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );

    final copiedFile = await service.copyImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "copy-idempotent-guid",
      assetId: "copy/idempotent",
    );
    sourceFile.writeAsBytesSync(<int>[0xff, 0xd8, 0x06, 0xff, 0xd9]);

    final secondCopy = await service.copyImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "copy-idempotent-guid",
      assetId: "copy/idempotent",
    );

    expect(secondCopy.path, copiedFile.path);
    expect(
      File(copiedFile.path).readAsBytesSync(),
      <int>[0xff, 0xd8, 0x05, 0xff, 0xd9],
    );
  });

  test("attachImportedMedia copies and registers gallery photos", () async {
    final sourceFile = File("${tempDir.path}/camera roll/photo two.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0x01, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );
    final capturedAt = DateTime.utc(2026, 6, 17, 15, 30);

    SessionManager.instance.startSession(
      "gallery-guid",
      "gallery-id",
      deviceType: "Master",
    );

    await service.attachImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "gallery-guid",
      assetId: "gallery/photo:two",
      assetType: AssetType.image,
      createDateTime: capturedAt,
      videoDuration: Duration.zero,
      deviceId: "device-1",
    );

    final photos = SessionManager.instance.currentSession?.capturedPhotos;
    expect(photos, hasLength(1));
    final importedPhotoPath = photos!.single.photoPath;
    expect(
      importedPhotoPath,
      "${tempDir.path}/session_gallery-guid/"
      "gallery_gallery_photo_two_photo two.jpg",
    );
    expect(File(importedPhotoPath).readAsBytesSync(),
        sourceFile.readAsBytesSync());
    expect(sourceFile.existsSync(), isTrue);

    final metadataFile = File(
      "${tempDir.path}/session_gallery-guid/metadata.json",
    );
    expect(metadataFile.existsSync(), isTrue);
    expect(await metadataFile.readAsString(), contains(importedPhotoPath));
  });

  test("attachImportedMedia rejects stale session guid before copying",
      () async {
    final sourceFile = File("${tempDir.path}/camera roll/stale.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0x07, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );

    SessionManager.instance.startSession(
      "active-gallery-guid",
      "active-gallery-id",
      deviceType: "Master",
    );

    await service.attachImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "stale-gallery-guid",
      assetId: "stale/photo",
      assetType: AssetType.image,
      createDateTime: DateTime.utc(2026, 6, 18, 16, 5),
      videoDuration: Duration.zero,
      deviceId: "device-1",
    );

    expect(SessionManager.instance.currentSession?.capturedPhotos, isEmpty);
    expect(
      Directory("${tempDir.path}/session_stale-gallery-guid").existsSync(),
      isFalse,
    );
    expect(
      File("${tempDir.path}/session_active-gallery-guid/metadata.json")
          .existsSync(),
      isFalse,
    );
    expect(sourceFile.existsSync(), isTrue);
  });

  test("attachImportedMedia does not duplicate the same gallery photo",
      () async {
    final sourceFile = File("${tempDir.path}/camera roll/duplicate.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0x02, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );

    SessionManager.instance.startSession(
      "duplicate-gallery-guid",
      "duplicate-gallery-id",
      deviceType: "Master",
    );

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await service.attachImportedMedia(
        sourceFile: sourceFile,
        sessionGuid: "duplicate-gallery-guid",
        assetId: "duplicate/photo",
        assetType: AssetType.image,
        createDateTime: DateTime.utc(2026, 6, 17, 16, 0),
        videoDuration: Duration.zero,
        deviceId: "device-1",
      );
    }

    final photos = SessionManager.instance.currentSession?.capturedPhotos;
    expect(photos, hasLength(1));

    final metadataFile = File(
      "${tempDir.path}/session_duplicate-gallery-guid/metadata.json",
    );
    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    expect(metadata["photos"], hasLength(1));
  });

  test("duplicate gallery attachment does not overwrite the session copy",
      () async {
    final sourceFile = File("${tempDir.path}/camera roll/overwrite.jpg")
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0x03, 0xff, 0xd9]);
    final service = GallerySessionAttachmentService(
      documentsDirectoryProvider: () async => tempDir,
    );

    SessionManager.instance.startSession(
      "duplicate-copy-guid",
      "duplicate-copy-id",
      deviceType: "Master",
    );

    await service.attachImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "duplicate-copy-guid",
      assetId: "duplicate/copy",
      assetType: AssetType.image,
      createDateTime: DateTime.utc(2026, 6, 17, 16, 15),
      videoDuration: Duration.zero,
      deviceId: "device-1",
    );

    final importedPhotoPath =
        SessionManager.instance.currentSession!.capturedPhotos.single.photoPath;
    sourceFile.writeAsBytesSync(<int>[0xff, 0xd8, 0x04, 0xff, 0xd9]);

    await service.attachImportedMedia(
      sourceFile: sourceFile,
      sessionGuid: "duplicate-copy-guid",
      assetId: "duplicate/copy",
      assetType: AssetType.image,
      createDateTime: DateTime.utc(2026, 6, 17, 16, 15),
      videoDuration: Duration.zero,
      deviceId: "device-1",
    );

    expect(
      File(importedPhotoPath).readAsBytesSync(),
      <int>[0xff, 0xd8, 0x03, 0xff, 0xd9],
    );
    expect(
      SessionManager.instance.currentSession?.capturedPhotos,
      hasLength(1),
    );
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.documentsDir);

  final Directory documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return documentsDir.path;
  }
}
