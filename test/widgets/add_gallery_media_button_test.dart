import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/captured_photo.dart";
import "package:hydracam/services/gallery_session_attachment_service.dart";
import "package:hydracam/services/session_manager.dart";
import "package:hydracam/widgets/add_gallery_media_button.dart";
import "package:photo_manager/photo_manager.dart";
// ignore: depend_on_referenced_packages
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const photoManagerChannel = MethodChannel("com.fluttercandies/photo_manager");
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, null);
    if (SessionManager.instance.isSessionActive) {
      await SessionManager.instance.endSession();
    }
    testPathProvider.dispose();
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
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: GallerySessionAttachmentService(
              documentsDirectoryProvider: () async =>
                  testPathProvider.documentsDir,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();

    expect(find.text("Select Media Filters"), findsOneWidget);
    expect(find.text("Browse All"), findsOneWidget);
    expect(find.text("Apply"), findsOneWidget);
  });

  testWidgets("gallery load errors are reported without crashing",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "device_id": "gallery-import-device",
    });
    final photoManagerCalls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, (call) async {
      photoManagerCalls.add(call.method);
      switch (call.method) {
        case "requestPermissionExtend":
          return 3; // PermissionState.authorized
        case "getAssetPathList":
          throw PlatformException(
            code: "gallery_unavailable",
            message: "Gallery provider unavailable",
          );
      }
      throw UnsupportedError("Unexpected photo_manager call ${call.method}");
    });
    final galleryAttachmentService = _SynchronousGalleryAttachmentService(
      documentsDir: testPathProvider.documentsDir,
    );

    SessionManager.instance.startSession(
      "gallery-load-error-guid",
      "gallery-load-error-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: galleryAttachmentService,
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(photoManagerCalls, contains("getAssetPathList"));
    expect(galleryAttachmentService.calls, isEmpty);
    expect(find.text("Could not load gallery media"), findsOneWidget);
  });

  testWidgets("selected gallery media is copied into the active session",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "device_id": "gallery-import-device",
    });
    final sourceFile = File("${testPathProvider.documentsDir.path}/source.jpg")
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0xff, 0xd9]);
    final createdAt = DateTime.utc(2026, 6, 17, 15, 30);
    final photoManagerCalls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, (call) async {
      photoManagerCalls.add(call.method);
      switch (call.method) {
        case "requestPermissionExtend":
          return 3; // PermissionState.authorized
        case "getAssetPathList":
          return {
            "data": [
              {
                "id": "gallery-album",
                "name": "Gallery",
                "assetCount": 1,
                "isAll": true,
                "albumType": 1,
              },
            ],
          };
        case "getAssetListPaged":
          return {
            "data": [
              {
                "id": "gallery-photo-1",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "source.jpg",
                "createDt": createdAt.millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
            ],
          };
        case "getThumb":
          return null;
        case "getFullFile":
          return sourceFile.path;
      }
      throw UnsupportedError("Unexpected photo_manager call ${call.method}");
    });
    final galleryAttachmentService = _SynchronousGalleryAttachmentService(
      documentsDir: testPathProvider.documentsDir,
    );

    SessionManager.instance.startSession(
      "gallery-copy-guid",
      "gallery-copy-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: galleryAttachmentService,
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.runAsync(() async {
      await tester.tap(find.text("Done"));
      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (SessionManager.instance.currentSession?.capturedPhotos.isNotEmpty ??
            false) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(photoManagerCalls, contains("getFullFile"));
    expect(galleryAttachmentService.calls, hasLength(1));
    expect(galleryAttachmentService.calls.single.assetId, "gallery-photo-1");
    expect(
      galleryAttachmentService.calls.single.sessionGuid,
      "gallery-copy-guid",
    );
    expect(galleryAttachmentService.calls.single.sourcePath, sourceFile.path);
    final photos = SessionManager.instance.currentSession?.capturedPhotos;
    expect(photos, hasLength(1));
    final importedPhotoPath = photos!.single.photoPath;
    expect(importedPhotoPath, isNot(sourceFile.path));
    expect(
      importedPhotoPath,
      startsWith(
        "${testPathProvider.documentsDir.path}/session_gallery-copy-guid/",
      ),
    );
    expect(
      File(importedPhotoPath).readAsBytesSync(),
      sourceFile.readAsBytesSync(),
    );
  });

  testWidgets("unavailable selected gallery media reports no import",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "device_id": "gallery-import-device",
    });
    final createdAt = DateTime.utc(2026, 6, 17, 16, 30);
    final photoManagerCalls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, (call) async {
      photoManagerCalls.add(call.method);
      switch (call.method) {
        case "requestPermissionExtend":
          return 3; // PermissionState.authorized
        case "getAssetPathList":
          return {
            "data": [
              {
                "id": "gallery-album",
                "name": "Gallery",
                "assetCount": 1,
                "isAll": true,
                "albumType": 1,
              },
            ],
          };
        case "getAssetListPaged":
          return {
            "data": [
              {
                "id": "missing-gallery-photo",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "missing.jpg",
                "createDt": createdAt.millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
            ],
          };
        case "getThumb":
          return null;
        case "getFullFile":
          return null;
      }
      throw UnsupportedError("Unexpected photo_manager call ${call.method}");
    });
    final galleryAttachmentService = _SynchronousGalleryAttachmentService(
      documentsDir: testPathProvider.documentsDir,
    );

    SessionManager.instance.startSession(
      "gallery-missing-file-guid",
      "gallery-missing-file-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: galleryAttachmentService,
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.runAsync(() async {
      await tester.tap(find.text("Done"));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(photoManagerCalls, contains("getFullFile"));
    expect(galleryAttachmentService.calls, isEmpty);
    expect(SessionManager.instance.currentSession?.capturedPhotos, isEmpty);
    expect(find.text("No gallery media was added"), findsOneWidget);
    expect(find.text("Media added to session"), findsNothing);
  });

  testWidgets("partially unavailable selected gallery media reports skipped",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "device_id": "gallery-import-device",
    });
    final sourceFile =
        File("${testPathProvider.documentsDir.path}/partial-source.jpg")
          ..writeAsBytesSync(<int>[0xff, 0xd8, 0x07, 0xff, 0xd9]);
    final createdAt = DateTime.utc(2026, 6, 17, 17, 0);
    final photoManagerCalls = <String>[];
    var fullFileCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, (call) async {
      photoManagerCalls.add(call.method);
      switch (call.method) {
        case "requestPermissionExtend":
          return 3; // PermissionState.authorized
        case "getAssetPathList":
          return {
            "data": [
              {
                "id": "gallery-album",
                "name": "Gallery",
                "assetCount": 2,
                "isAll": true,
                "albumType": 1,
              },
            ],
          };
        case "getAssetListPaged":
          return {
            "data": [
              {
                "id": "partial-gallery-photo",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "partial-source.jpg",
                "createDt": createdAt.millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
              {
                "id": "missing-gallery-photo",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "missing.jpg",
                "createDt": createdAt
                        .subtract(const Duration(minutes: 1))
                        .millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
            ],
          };
        case "getThumb":
          return null;
        case "getFullFile":
          fullFileCalls += 1;
          return fullFileCalls == 1 ? sourceFile.path : null;
      }
      throw UnsupportedError("Unexpected photo_manager call ${call.method}");
    });
    final galleryAttachmentService = _SynchronousGalleryAttachmentService(
      documentsDir: testPathProvider.documentsDir,
    );

    SessionManager.instance.startSession(
      "gallery-partial-guid",
      "gallery-partial-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: galleryAttachmentService,
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).at(0));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.runAsync(() async {
      await tester.tap(find.text("Done"));
      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (SessionManager.instance.currentSession?.capturedPhotos.isNotEmpty ??
            false) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(photoManagerCalls.where((method) => method == "getFullFile"),
        hasLength(2));
    expect(galleryAttachmentService.calls, hasLength(1));
    expect(
        galleryAttachmentService.calls.single.assetId, "partial-gallery-photo");
    expect(
        SessionManager.instance.currentSession?.capturedPhotos, hasLength(1));
    expect(find.text("1 gallery media item added, 1 skipped"), findsOneWidget);
    expect(find.text("Media added to session"), findsNothing);
  });

  testWidgets("gallery import continues after one selected asset fails",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      "autoUploadMaterials": false,
      "deleteLocalAfterUpload": false,
      "device_id": "gallery-import-device",
    });
    final failedSourceFile =
        File("${testPathProvider.documentsDir.path}/failed-source.jpg")
          ..writeAsBytesSync(<int>[0xff, 0xd8, 0x08, 0xff, 0xd9]);
    final importedSourceFile =
        File("${testPathProvider.documentsDir.path}/imported-source.jpg")
          ..writeAsBytesSync(<int>[0xff, 0xd8, 0x09, 0xff, 0xd9]);
    final createdAt = DateTime.utc(2026, 6, 17, 17, 30);
    final photoManagerCalls = <String>[];
    var fullFileCalls = 0;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManagerChannel, (call) async {
      photoManagerCalls.add(call.method);
      switch (call.method) {
        case "requestPermissionExtend":
          return 3; // PermissionState.authorized
        case "getAssetPathList":
          return {
            "data": [
              {
                "id": "gallery-album",
                "name": "Gallery",
                "assetCount": 2,
                "isAll": true,
                "albumType": 1,
              },
            ],
          };
        case "getAssetListPaged":
          return {
            "data": [
              {
                "id": "failed-gallery-photo",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "failed-source.jpg",
                "createDt": createdAt.millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
              {
                "id": "imported-gallery-photo",
                "type": 1,
                "width": 120,
                "height": 80,
                "duration": 0,
                "title": "imported-source.jpg",
                "createDt": createdAt
                        .subtract(const Duration(minutes: 1))
                        .millisecondsSinceEpoch ~/
                    Duration.millisecondsPerSecond,
              },
            ],
          };
        case "getThumb":
          return null;
        case "getFullFile":
          fullFileCalls += 1;
          return fullFileCalls == 1
              ? failedSourceFile.path
              : importedSourceFile.path;
      }
      throw UnsupportedError("Unexpected photo_manager call ${call.method}");
    });
    final galleryAttachmentService = _SynchronousGalleryAttachmentService(
      documentsDir: testPathProvider.documentsDir,
      failedAssetIds: {"failed-gallery-photo"},
    );

    SessionManager.instance.startSession(
      "gallery-failure-guid",
      "gallery-failure-id",
      deviceType: "Master",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddGalleryMediaButton(
            galleryAttachmentService: galleryAttachmentService,
          ),
        ),
      ),
    );

    await tester.tap(find.text("Add Media from Gallery"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Browse All"));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).at(0));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.runAsync(() async {
      await tester.tap(find.text("Done"));
      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (SessionManager.instance.currentSession?.capturedPhotos.isNotEmpty ??
            false) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(photoManagerCalls.where((method) => method == "getFullFile"),
        hasLength(2));
    expect(galleryAttachmentService.calls, hasLength(2));
    expect(
        SessionManager.instance.currentSession?.capturedPhotos, hasLength(1));
    expect(
      SessionManager.instance.currentSession?.capturedPhotos.single.photoPath,
      contains("imported-gallery-photo"),
    );
    expect(find.text("1 gallery media item added, 1 skipped"), findsOneWidget);
  });
}

class _SynchronousGalleryAttachmentService
    extends GallerySessionAttachmentService {
  _SynchronousGalleryAttachmentService({
    required this.documentsDir,
    this.failedAssetIds = const {},
  });

  final Directory documentsDir;
  final Set<String> failedAssetIds;
  final List<_GalleryAttachmentCall> calls = [];

  @override
  Future<void> attachImportedMedia({
    required File sourceFile,
    required String sessionGuid,
    required String assetId,
    required AssetType assetType,
    required DateTime createDateTime,
    required Duration videoDuration,
    required String deviceId,
  }) {
    calls.add(
      _GalleryAttachmentCall(
        sourcePath: sourceFile.path,
        sessionGuid: sessionGuid,
        assetId: assetId,
      ),
    );
    if (failedAssetIds.contains(assetId)) {
      throw StateError("Failed to attach $assetId");
    }
    final destination = File(
      "${documentsDir.path}/session_$sessionGuid/gallery_${assetId}_"
      "${sourceFile.uri.pathSegments.last}",
    )..createSync(recursive: true);
    destination.writeAsBytesSync(sourceFile.readAsBytesSync());
    if (assetType == AssetType.image) {
      SessionManager.instance.currentSession?.addPhoto(
        CapturedPhoto(
          photoPath: destination.path,
          captureDate: createDateTime,
          receivedDate: DateTime.now(),
          slaveDeviceId: deviceId,
        ),
      );
    }
    return Future.value();
  }
}

class _GalleryAttachmentCall {
  const _GalleryAttachmentCall({
    required this.sourcePath,
    required this.sessionGuid,
    required this.assetId,
  });

  final String sourcePath;
  final String sessionGuid;
  final String assetId;
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
