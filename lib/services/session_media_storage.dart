import "dart:io";
import "dart:typed_data";

import "package:path_provider/path_provider.dart";

import "gallery_persistence_service.dart";

enum SessionMediaType { photo, video }

typedef DocumentsDirectoryProvider = Future<Directory> Function();
typedef GalleryMediaPersistor = Future<void> Function(
  String filePath,
  SessionMediaType mediaType,
);

class SessionMediaStorage {
  SessionMediaStorage({
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    GalleryMediaPersistor? galleryMediaPersistor,
    DateTime Function()? now,
  })  : _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _galleryMediaPersistor =
            galleryMediaPersistor ?? _persistMediaToGallery,
        _now = now ?? DateTime.now;

  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final GalleryMediaPersistor _galleryMediaPersistor;
  final DateTime Function() _now;

  Future<String> saveReceivedMedia({
    required Uint8List binaryData,
    required String? sessionGuid,
    required SessionMediaType mediaType,
  }) async {
    if (sessionGuid == null || sessionGuid.isEmpty) {
      throw StateError(
          "Cannot save received media without an active session GUID.");
    }
    if (binaryData.isEmpty) {
      throw ArgumentError.value(binaryData, "binaryData", "must not be empty");
    }

    final documentsDirectory = await _documentsDirectoryProvider();
    final sessionDirectory =
        Directory("${documentsDirectory.path}/session_$sessionGuid");
    await sessionDirectory.create(recursive: true);

    final fileExtension = _fileExtensionFor(mediaType);
    final filePath = "${sessionDirectory.path}/media_"
        "${_now().millisecondsSinceEpoch}.$fileExtension";
    final file = File(filePath);
    await file.writeAsBytes(binaryData);
    await _galleryMediaPersistor(filePath, mediaType);
    return filePath;
  }

  String _fileExtensionFor(SessionMediaType mediaType) {
    return switch (mediaType) {
      SessionMediaType.photo => "jpg",
      SessionMediaType.video => "mp4",
    };
  }

  static Future<void> _persistMediaToGallery(
    String filePath,
    SessionMediaType mediaType,
  ) async {
    switch (mediaType) {
      case SessionMediaType.photo:
        await GalleryPersistenceService.savePhoto(filePath);
      case SessionMediaType.video:
        await GalleryPersistenceService.saveVideo(filePath);
    }
  }
}
