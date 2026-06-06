import "dart:io";
import "package:photo_manager/photo_manager.dart";

import "log_service.dart";

/// Handles saving photos and videos to the device gallery under the HydraCam album.
// ignore: avoid_classes_with_only_static_members
class GalleryPersistenceService {
  static const String _albumName = "HydraCam";
  static bool _hasPermission = false;

  static Future<void> savePhoto(String filePath) async {
    await _saveMedia(filePath, isPhoto: true);
  }

  static Future<void> saveVideo(String filePath) async {
    await _saveMedia(filePath, isPhoto: false);
  }

  static Future<void> _saveMedia(String filePath,
      {required bool isPhoto}) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      LogService.instance.registerLog(
          "GalleryPersistenceService: File not found -> $filePath");
      return;
    }

    if (!await _ensurePermission()) {
      return;
    }

    try {
      final filename = file.uri.pathSegments.last;

      if (isPhoto) {
        await PhotoManager.editor.saveImageWithPath(
          filePath,
          title: filename,
          relativePath: _albumName,
        );
      } else {
        await PhotoManager.editor.saveVideo(
          file,
          title: filename,
          relativePath: _albumName,
        );
      }

      LogService.instance.registerLog(
          "GalleryPersistenceService: Saved media ${file.uri.pathSegments.last} to gallery");
    } catch (error) {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Failed to save media ($filePath) -> $error");
    }
  }

  static Future<bool> _ensurePermission() async {
    if (_hasPermission) {
      return true;
    }

    final PermissionState state = await PhotoManager.requestPermissionExtend();
    _hasPermission = state.hasAccess;

    if (!_hasPermission) {
      LogService.instance
          .registerLog("GalleryPersistenceService: Photos permission denied.");
    }

    return _hasPermission;
  }
}
