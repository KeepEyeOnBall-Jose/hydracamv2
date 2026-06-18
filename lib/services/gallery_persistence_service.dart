import "dart:async";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:photo_manager/photo_manager.dart";

import "log_service.dart";

typedef GalleryPermissionRequester = Future<bool> Function();
typedef GalleryPhotoSaver = Future<void> Function(
  String filePath,
  String filename,
);
typedef GalleryVideoSaver = Future<void> Function(
  File file,
  String filename,
);

/// Handles saving photos and videos to the device gallery under the HydraCam album.
// ignore: avoid_classes_with_only_static_members
class GalleryPersistenceService {
  static const String _albumName = "HydraCam";
  static const Duration _defaultOperationTimeout = Duration(seconds: 8);

  static Duration _operationTimeout = _defaultOperationTimeout;
  static GalleryPermissionRequester _permissionRequester =
      _requestPhotoManagerPermission;
  static GalleryPhotoSaver _photoSaver = _savePhotoWithPhotoManager;
  static GalleryVideoSaver _videoSaver = _saveVideoWithPhotoManager;
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
        await _photoSaver(filePath, filename).timeout(_operationTimeout);
      } else {
        await _videoSaver(file, filename).timeout(_operationTimeout);
      }

      LogService.instance.registerLog(
          "GalleryPersistenceService: Saved media ${file.uri.pathSegments.last} to gallery");
    } on TimeoutException {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Timed out saving media to gallery "
          "after ${_formatDuration(_operationTimeout)}; keeping media in "
          "the session directory only. $filePath");
    } catch (error) {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Failed to save media ($filePath) -> $error");
    }
  }

  static Future<bool> _ensurePermission() async {
    if (_hasPermission) {
      return true;
    }

    try {
      _hasPermission = await _permissionRequester().timeout(_operationTimeout);
    } on TimeoutException {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Timed out requesting gallery permission "
          "after ${_formatDuration(_operationTimeout)}; keeping media in "
          "the session directory only.");
      return false;
    } on MissingPluginException catch (error) {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Gallery plugin is unavailable on this "
          "platform; keeping media in the session directory only. $error");
      return false;
    } catch (error) {
      LogService.instance.registerLog(
          "GalleryPersistenceService: Failed to request gallery permission; "
          "keeping media in the session directory only. $error");
      return false;
    }

    if (!_hasPermission) {
      LogService.instance
          .registerLog("GalleryPersistenceService: Photos permission denied.");
    }

    return _hasPermission;
  }

  static Future<bool> _requestPhotoManagerPermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    return state.hasAccess;
  }

  static Future<void> _savePhotoWithPhotoManager(
    String filePath,
    String filename,
  ) async {
    await PhotoManager.editor.saveImageWithPath(
      filePath,
      title: filename,
      relativePath: _albumName,
    );
  }

  static Future<void> _saveVideoWithPhotoManager(
    File file,
    String filename,
  ) async {
    await PhotoManager.editor.saveVideo(
      file,
      title: filename,
      relativePath: _albumName,
    );
  }

  static String _formatDuration(Duration duration) {
    if (duration.inSeconds >= 1) {
      return "${duration.inSeconds}s";
    }
    return "${duration.inMilliseconds}ms";
  }

  @visibleForTesting
  static void configureForTesting({
    Duration? operationTimeout,
    GalleryPermissionRequester? permissionRequester,
    GalleryPhotoSaver? photoSaver,
    GalleryVideoSaver? videoSaver,
  }) {
    _operationTimeout = operationTimeout ?? _operationTimeout;
    _permissionRequester = permissionRequester ?? _permissionRequester;
    _photoSaver = photoSaver ?? _photoSaver;
    _videoSaver = videoSaver ?? _videoSaver;
    _hasPermission = false;
  }

  @visibleForTesting
  static void resetForTesting() {
    _operationTimeout = _defaultOperationTimeout;
    _permissionRequester = _requestPhotoManagerPermission;
    _photoSaver = _savePhotoWithPhotoManager;
    _videoSaver = _saveVideoWithPhotoManager;
    _hasPermission = false;
  }
}
