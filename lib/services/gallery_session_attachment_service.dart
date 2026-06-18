import "dart:io";

import "package:path_provider/path_provider.dart";
import "package:photo_manager/photo_manager.dart";

import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "log_service.dart";
import "session_manager.dart";

typedef GalleryDocumentsDirectoryProvider = Future<Directory> Function();

class GallerySessionAttachmentService {
  const GallerySessionAttachmentService({
    this.documentsDirectoryProvider,
  });

  final GalleryDocumentsDirectoryProvider? documentsDirectoryProvider;

  Future<void> attachImportedMedia({
    required File sourceFile,
    required String sessionGuid,
    required String assetId,
    required AssetType assetType,
    required DateTime createDateTime,
    required Duration videoDuration,
    required String deviceId,
  }) async {
    if (!_isCurrentSession(sessionGuid)) {
      LogService.instance.registerLog(
        "Skipping gallery attachment for inactive session GUID: "
        "$sessionGuid (active: ${SessionManager.instance.sessionGuid ?? 'none'})",
      );
      return;
    }

    final sessionFile = await _sessionFileFor(
      sourceFile: sourceFile,
      sessionGuid: sessionGuid,
      assetId: assetId,
    );

    if (assetType == AssetType.image) {
      final alreadyAttached = SessionManager
              .instance.currentSession?.capturedPhotos
              .any((photo) => photo.photoPath == sessionFile.path) ??
          false;
      if (alreadyAttached) {
        LogService.instance.registerLog(
          "Skipping duplicate gallery photo attachment: ${sessionFile.path}",
        );
        return;
      }
      final attachedFile = await _copyImportedMediaToSessionFile(
        sourceFile: sourceFile,
        destination: sessionFile,
      );
      final photo = CapturedPhoto(
        photoPath: attachedFile.path,
        captureDate: createDateTime,
        receivedDate: DateTime.now(),
        slaveDeviceId: deviceId,
      );
      await SessionManager.instance.addPhoto(photo);
    } else if (assetType == AssetType.video) {
      final alreadyAttached = SessionManager
              .instance.currentSession?.capturedVideos
              .any((video) => video.videoPath == sessionFile.path) ??
          false;
      if (alreadyAttached) {
        LogService.instance.registerLog(
          "Skipping duplicate gallery video attachment: ${sessionFile.path}",
        );
        return;
      }
      final attachedFile = await _copyImportedMediaToSessionFile(
        sourceFile: sourceFile,
        destination: sessionFile,
      );
      final video = CapturedVideo(
        videoPath: attachedFile.path,
        startRecordingDate: createDateTime,
        endRecordingDate: createDateTime.add(videoDuration),
        receivedDate: DateTime.now(),
        slaveDeviceId: deviceId,
      );
      await SessionManager.instance.addVideo(video);
    }
  }

  bool _isCurrentSession(String sessionGuid) {
    final activeGuid = SessionManager.instance.sessionGuid?.trim();
    return activeGuid != null &&
        activeGuid.isNotEmpty &&
        activeGuid == sessionGuid.trim();
  }

  Future<File> copyImportedMedia({
    required File sourceFile,
    required String sessionGuid,
    required String assetId,
  }) async {
    final destination = await _sessionFileFor(
      sourceFile: sourceFile,
      sessionGuid: sessionGuid,
      assetId: assetId,
    );
    return _copyImportedMediaToSessionFile(
      sourceFile: sourceFile,
      destination: destination,
    );
  }

  Future<File> _copyImportedMediaToSessionFile({
    required File sourceFile,
    required File destination,
  }) async {
    if (sourceFile.path == destination.path) {
      return sourceFile;
    }
    if (await destination.exists()) {
      LogService.instance.registerLog(
        "Reusing existing gallery media session copy: ${destination.path}",
      );
      return destination;
    }

    LogService.instance.registerLog(
      "Copying gallery media into session: ${sourceFile.path} -> "
      "${destination.path}",
    );
    final copiedFile = await sourceFile.copy(destination.path);
    LogService.instance.registerLog(
      "Copied gallery media into session: ${copiedFile.path}",
    );
    return copiedFile;
  }

  Future<File> _sessionFileFor({
    required File sourceFile,
    required String sessionGuid,
    required String assetId,
  }) async {
    final documentsDirectory = documentsDirectoryProvider == null
        ? await getApplicationDocumentsDirectory()
        : await documentsDirectoryProvider!();
    final sessionDirectory =
        Directory("${documentsDirectory.path}/session_$sessionGuid");
    await sessionDirectory.create(recursive: true);

    final sourceFileName = sourceFile.uri.pathSegments.isEmpty
        ? "media"
        : sourceFile.uri.pathSegments.last;
    final safeAssetId = assetId.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
    return File(
      "${sessionDirectory.path}/gallery_${safeAssetId}_$sourceFileName",
    );
  }
}
