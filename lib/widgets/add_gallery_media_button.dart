import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../app_theme.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/device_service.dart';
import '../services/session_manager.dart';
import '../services/log_service.dart';
import 'media_filter_dialog.dart';
import 'media_selection_screen.dart';

/// A button widget that allows adding media from the gallery to the current session.
class AddGalleryMediaButton extends StatefulWidget {
  final bool enabled; // New parameter to control enable/disable state

  const AddGalleryMediaButton({Key? key, this.enabled = true}) : super(key: key);

  @override
  _AddGalleryMediaButtonState createState() => _AddGalleryMediaButtonState();
}

class _AddGalleryMediaButtonState extends State<AddGalleryMediaButton> {
  @override
  void initState() {
    super.initState();
    // Listen to session changes
    SessionManager.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    // Remove listener
    SessionManager.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    setState(() {});
  }

  void _onPressed() async {
    if (!SessionManager.instance.isSessionActive) {
      _showNoSessionAlert();
      return;
    }

    final hasPermission = await _checkGalleryPermissions();
    if (!hasPermission) {
      _showPermissionsAlert();
      return;
    }

    _openFilterDialog();
  }

  Future<bool> _checkGalleryPermissions() async {
    PermissionState permission = await PhotoManager.requestPermissionExtend();
    return permission.isAuth;
  }

  void _showNoSessionAlert() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('No Active Session'),
          content: const Text('Please start a session before adding media from the gallery.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionsAlert() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text(
              'Please grant gallery permissions to access media. Go to app settings to enable permissions.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await PhotoManager.openSetting();
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _openFilterDialog() async {
    final filters = await showDialog<MediaFilters>(
      context: context,
      builder: (context) {
        return const MediaFilterDialog();
      },
    );

    if (filters != null) {
      _queryAndSelectMedia(filters);
    }
  }

  Future<List<AssetEntity>> _fetchMedia(MediaFilters filters) async {
    FilterOptionGroup options = FilterOptionGroup();

    if (filters.isPhoto) {
      options.setOption(
        AssetType.image,
        const FilterOption(),
      );
    } else {
      options.setOption(
        AssetType.video,
        FilterOption(
          durationConstraint: filters.minDuration != null
              ? DurationConstraint(min: filters.minDuration!)
              : const DurationConstraint(),
        ),
      );
    }

    if (filters.startDate != null || filters.endDate != null) {
      options.createTimeCond = DateTimeCond(
        min: filters.startDate ?? DateTime(2000, 1, 1),
        max: filters.endDate ?? DateTime(2100, 1, 1),
      );
    }

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: filters.isPhoto ? RequestType.image : RequestType.video,
      filterOption: options,
    );

    List<AssetEntity> allMedia = [];
    for (var album in albums) {
      allMedia.addAll(await album.getAssetListPaged(page: 0, size: 100));
      LogService.instance.registerLog('Album: ${album.name}');
    }

    return allMedia;
  }

  Future<void> _queryAndSelectMedia(MediaFilters filters) async {
    List<AssetEntity> media = await _fetchMedia(filters);

    if (media.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No media found with the specified filters')),
        );
      }
      return;
    }

    if (context.mounted) {
      final selectedMedia = await Navigator.push<List<AssetEntity>>(
        context,
        MaterialPageRoute(
          builder: (context) => MediaSelectionScreen(
            mediaList: media,
          ),
        ),
      );

      if (selectedMedia != null && selectedMedia.isNotEmpty) {
        await _addMediaToSession(selectedMedia);
      }
    }
  }

  Future<void> _addMediaToSession(List<AssetEntity> selectedMedia) async {
    final String deviceId = await DeviceIdService.getOrCreateDeviceId();

    for (var asset in selectedMedia) {
      File? file = await asset.file;
      if (file == null) continue;

      if (asset.type == AssetType.image) {
        CapturedPhoto photo = CapturedPhoto(
          photoPath: file.path,
          captureDate: asset.createDateTime,
          receivedDate: DateTime.now(),
          slaveDeviceId: deviceId,
        );
        SessionManager.instance.addPhoto(photo);
      } else if (asset.type == AssetType.video) {
        CapturedVideo video = CapturedVideo(
          videoPath: file.path,
          startRecordingDate: asset.createDateTime,
          endRecordingDate: asset.createDateTime.add(asset.videoDuration),
          receivedDate: DateTime.now(),
          slaveDeviceId: deviceId,
        );
        SessionManager.instance.addVideo(video);
      }
    }

    SessionManager.instance.notifyListeners();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media added to session')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool sessionActive = SessionManager.instance.isSessionActive;
    bool isButtonEnabled = widget.enabled && sessionActive;
    return ElevatedButton(
      onPressed: isButtonEnabled ? _onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isButtonEnabled ? null : AppTheme.disabledButtonColor,
      ),
      child: const Text('Add Media from Gallery'),
    );
  }
}
