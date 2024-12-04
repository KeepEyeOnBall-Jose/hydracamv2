import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../app_theme.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/device_service.dart';
import '../services/session_manager.dart';
import '../services/log_service.dart';
import '../services/permission_service.dart';
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
      // Show error alert if no active session
      _showNoSessionAlert();
      return;
    }

    // TODO: Check permissions (avoiding storage troll one)

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

  // TODO: Remove or use
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
      if (context.mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No media found with the specified filters')),
        );
      }
      return;
    }

    // Show media selection screen
    if (context.mounted){
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

    // Fetch all albums
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: filters.isPhoto ? RequestType.image : RequestType.video,
      filterOption: filterOptionGroup,
    );

    if (albums.isEmpty) {
      return [];
    }

    for (var album in albums) {
      LogService.instance.registerLog('Album: ${album.name}');
    }


    // Collect all media from each album
    Map<String, AssetEntity> allMediaMap = {};  // Use a map so we can track ids and avoid duplicates
    for (var album in albums) {
      List<AssetEntity> mediaInAlbum = await album.getAssetListPaged(page: 0, size: 1000);
      for (var asset in mediaInAlbum) {
        // Add only if id is not already present in the map
        if (!allMediaMap.containsKey(asset.id)) {
          allMediaMap[asset.id] = asset;
        }
      }
    }

    List<AssetEntity> allMedia = allMediaMap.values.toList();

    // Return the combined list of all media
    return allMedia;
  }


  Future<void> _addMediaToSession(List<AssetEntity> selectedMedia) async {

    // Get the device ID
    final String deviceId = await DeviceIdService.getOrCreateDeviceId();

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
          slaveDeviceId: deviceId,
        );

        SessionManager.instance.addPhoto(photo);
      } else if (asset.type == AssetType.video) {
        CapturedVideo video = CapturedVideo(
          videoData: null,
          videoPath: file.path,
          slaveDeviceId: deviceId,
          startRecordingDate: createDate,
          endRecordingDate: createDate.add(asset.videoDuration),
          receivedDate: now,
        );

        SessionManager.instance.addVideo(video);
      }
    }

    // Notify listeners to update UI
    SessionManager.instance.notifyListeners();

    // Show confirmation
    if (context.mounted){
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
        backgroundColor: isButtonEnabled ? null : AppTheme.disabledButtonColor, // Optional style for disabled state
      ),
      child: const Text('Add Media from Gallery'),
    );
  }
}
