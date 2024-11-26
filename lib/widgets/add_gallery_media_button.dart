import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/session_manager.dart';
import '../services/log_service.dart';
import '../services/permission_service.dart';
import 'media_filter_dialog.dart';
import 'media_selection_screen.dart';

/// A button widget that allows adding media from the gallery to the current session.
class AddGalleryMediaButton extends StatefulWidget {
  const AddGalleryMediaButton({Key? key}) : super(key: key);

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
      // Show error alert if no active session
      _showNoSessionAlert();
      return;
    }
    // Check and request permissions
    bool permissionsGranted = true; //await PermissionService.requestAllPermissions();
    if (!permissionsGranted) {
      // Show alert if permissions are not granted
      _showPermissionsAlert();
      return;
    }

    // Open filter dialog
    _openFilterDialog();
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
          content: const Text('Please grant gallery permissions to access media.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await PermissionService.openAppSettings();
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
      // Proceed to query media with the filters
      _queryAndSelectMedia(filters);
    }
  }

  void _queryAndSelectMedia(MediaFilters filters) async {
    // Query media with filters
    final List<AssetEntity> mediaList = await _fetchMedia(filters);

    if (mediaList.isEmpty) {
      // Show message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media found with the specified filters')),
      );
      return;
    }

    // Show media selection screen
    final selectedMedia = await Navigator.push<List<AssetEntity>>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(
          mediaList: mediaList,
        ),
      ),
    );

    if (selectedMedia != null && selectedMedia.isNotEmpty) {
      // Add selected media to session
      await _addMediaToSession(selectedMedia);
    }
  }

  Future<List<AssetEntity>> _fetchMedia(MediaFilters filters) async {
    // Set up filter options
    FilterOptionGroup filterOptionGroup = FilterOptionGroup();

    // Media type filtering
    filterOptionGroup.setOption(
      filters.isPhoto ? AssetType.image : AssetType.video,
      filters.isPhoto
          ? const FilterOption() // For photos
          : FilterOption(
        durationConstraint: filters.minDuration != null
            ? DurationConstraint(min: filters.minDuration!)
            : const DurationConstraint(),
      ),
    );

    // Date range filtering
    if (filters.startDate != null || filters.endDate != null) {
      DateTime minDate = filters.startDate ?? DateTime(2000, 1, 1);
      DateTime maxDate = filters.endDate ?? DateTime(2100, 1, 1);

      filterOptionGroup.createTimeCond = DateTimeCond(
        min: minDate,
        max: maxDate,
      );
    }

    // Fetch albums
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      filterOption: filterOptionGroup,
    );

    if (albums.isEmpty) {
      return [];
    }

    // Fetch media from the default album
    AssetPathEntity album = albums.first;
    List<AssetEntity> mediaList = await album.getAssetListPaged(
      page: 0,
      size: 1000,
    );

    // Explicit filtering for the selected media type (in case the library returns mixed types)
    if (filters.isPhoto) {
      return mediaList.where((asset) => asset.type == AssetType.image).toList();
    } else {
      return mediaList.where((asset) => asset.type == AssetType.video).toList();
    }
  }


  Future<void> _addMediaToSession(List<AssetEntity> selectedMedia) async {
    for (var asset in selectedMedia) {
      File? file = await asset.file;
      if (file == null) continue;

      DateTime createDate = asset.createDateTime;
      DateTime now = DateTime.now();

      if (asset.type == AssetType.image) {
        CapturedPhoto photo = CapturedPhoto(
          photoData: null,
          photoPath: file.path,
          captureDate: createDate,
          receivedDate: now,
          slaveDeviceId: 'Gallery',
        );

        SessionManager.instance.addPhoto(photo);
      } else if (asset.type == AssetType.video) {
        CapturedVideo video = CapturedVideo(
          videoData: null,
          videoPath: file.path,
          slaveDeviceId: 'Gallery',
          startRecordingDate: createDate,
          endRecordingDate: createDate.add(asset.videoDuration ?? Duration.zero),
          receivedDate: now,
        );

        SessionManager.instance.addVideo(video);
      }
    }

    // Notify listeners to update UI
    SessionManager.instance.notifyListeners();

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Media added to session')),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool sessionActive = SessionManager.instance.isSessionActive;
    return ElevatedButton(
      onPressed: sessionActive ? _onPressed : null,
      child: const Text('Add Media from Gallery'),
    );
  }
}
