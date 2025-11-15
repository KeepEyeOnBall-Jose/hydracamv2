import "dart:io";
import "package:flutter/material.dart";
import "package:photo_manager/photo_manager.dart";
import "../app_theme.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/device_service.dart";
import "../services/session_manager.dart";
import "../services/log_service.dart";
import "media_filter_dialog.dart";
import "../screens/media_selection_screen.dart";

/// A button widget that allows adding media from the gallery to the current session.
class AddGalleryMediaButton extends StatefulWidget {
  final bool enabled; // New parameter to control enable/disable state

  const AddGalleryMediaButton({super.key, this.enabled = true});

  @override
  AddGalleryMediaButtonState createState() => AddGalleryMediaButtonState();
}

class AddGalleryMediaButtonState extends State<AddGalleryMediaButton> {
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

    _openFilterDialog();
  }

  void _showNoSessionAlert() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("No Active Session"),
          content: const Text(
              "Please start a session before adding media from the gallery."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
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
    final FilterOptionGroup options = FilterOptionGroup();

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

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: filters.isPhoto ? RequestType.image : RequestType.video,
      filterOption: options,
    );

    final Set<String> uniqueIds = {}; // Set to track unique asset IDs
    final List<AssetEntity> allMedia = [];

    for (var album in albums) {
      final assets = await album.getAssetListPaged(page: 0, size: 100);

      for (var asset in assets) {
        if (!uniqueIds.contains(asset.id)) {
          uniqueIds.add(asset.id); // Add the asset's ID to the set
          allMedia.add(asset); // Add the unique asset to the media list
        }
      }

      LogService.instance.registerLog(
          "Album: ${album.name}, Assets Processed: ${assets.length}");
    }

    // Sort media by creation date (most recent first)
    allMedia.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    return allMedia;
  }

  Future<void> _queryAndSelectMedia(MediaFilters filters) async {
    final List<AssetEntity> media = await _fetchMedia(filters);

    if (media.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("No media found with the specified filters")),
      );
      return;
    }

    if (!mounted) return;

    final selectedMedia = await Navigator.push<List<AssetEntity>>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(
          mediaList: media,
        ),
      ),
    );

    if (!mounted) return;

    if (selectedMedia != null && selectedMedia.isNotEmpty) {
      await _addMediaToSession(selectedMedia);
    }
  }

  Future<void> _addMediaToSession(List<AssetEntity> selectedMedia) async {
    final String deviceId = await DeviceIdService.getOrCreateDeviceId();

    for (var asset in selectedMedia) {
      final File? file = await asset.file;
      if (file == null) continue;

      if (asset.type == AssetType.image) {
        final CapturedPhoto photo = CapturedPhoto(
          photoPath: file.path,
          captureDate: asset.createDateTime,
          receivedDate: DateTime.now(),
          slaveDeviceId: deviceId,
        );
        SessionManager.instance.addPhoto(photo);
      } else if (asset.type == AssetType.video) {
        final CapturedVideo video = CapturedVideo(
          videoPath: file.path,
          startRecordingDate: asset.createDateTime,
          endRecordingDate: asset.createDateTime.add(asset.videoDuration),
          receivedDate: DateTime.now(),
          slaveDeviceId: deviceId,
        );
        SessionManager.instance.addVideo(video);
      }
    }

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    SessionManager.instance.notifyListeners();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Media added to session")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool sessionActive = SessionManager.instance.isSessionActive;
    final bool isButtonEnabled = widget.enabled && sessionActive;
    return ElevatedButton(
      onPressed: isButtonEnabled ? _onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isButtonEnabled ? null : AppTheme.disabledButtonColor,
      ),
      child: const Text("Add Media from Gallery"),
    );
  }
}
