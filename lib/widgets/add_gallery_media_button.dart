import "dart:async";
import "dart:io";
import "package:flutter/material.dart";
import "package:photo_manager/photo_manager.dart";
import "../app_theme.dart";
import "../services/device_service.dart";
import "../services/gallery_session_attachment_service.dart";
import "../services/gallery_session_candidate_source.dart";
import "../services/session_manager.dart";
import "../services/log_service.dart";
import "media_filter_dialog.dart";
import "../screens/media_selection_screen.dart";

/// A button widget that allows adding media from the gallery to the current session.
class AddGalleryMediaButton extends StatefulWidget {
  final bool enabled; // New parameter to control enable/disable state
  final GallerySessionAttachmentService galleryAttachmentService;

  const AddGalleryMediaButton({
    super.key,
    this.enabled = true,
    this.galleryAttachmentService = const GallerySessionAttachmentService(),
  });

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

  Future<void> _onPressed() async {
    if (!SessionManager.instance.isSessionActive) {
      _showNoSessionAlert();
      return;
    }

    await _openFilterDialog();
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

  Future<void> _openFilterDialog() async {
    final filters = await showDialog<MediaFilters>(
      context: context,
      builder: (context) {
        return const MediaFilterDialog();
      },
    );

    if (!mounted) {
      return;
    }

    if (filters != null) {
      await _queryAndSelectMedia(filters);
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

  Future<bool> _ensureGalleryPermission() async {
    final PermissionState state = await PhotoManager.requestPermissionExtend();
    if (state.hasAccess) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Gallery access is required to import media."),
      ),
    );
    return false;
  }

  Future<void> _queryAndSelectMedia(MediaFilters filters) async {
    final bool hasPermission = await _ensureGalleryPermission();
    if (!hasPermission) {
      return;
    }

    final List<AssetEntity> media;
    try {
      media = await _fetchMedia(filters);
    } catch (error) {
      LogService.instance.registerLog(
        "Failed to load gallery media for import: $error",
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not load gallery media")),
      );
      return;
    }

    if (media.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("No media found with the specified filters")),
      );
      return;
    }

    if (!mounted) return;

    final candidateSessions =
        await const GallerySessionCandidateSource().load();
    if (!mounted) return;

    final selectedMedia = await Navigator.push<List<AssetEntity>>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSelectionScreen(
          mediaList: media,
          candidateSessions: candidateSessions,
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
    var importedMediaCount = 0;
    var skippedMediaCount = 0;

    for (var asset in selectedMedia) {
      LogService.instance.registerLog(
        "Importing selected gallery asset into active session: ${asset.id}",
      );
      final File? file = await asset.file;
      if (file == null) {
        LogService.instance.registerLog(
          "Skipping gallery asset with no available local file: ${asset.id}",
        );
        skippedMediaCount += 1;
        continue;
      }
      LogService.instance.registerLog(
        "Resolved gallery asset file for import: ${file.path}",
      );
      final sessionGuid = SessionManager.instance.sessionGuid;
      if (sessionGuid == null || sessionGuid.isEmpty) {
        LogService.instance.registerLog(
          "Skipping gallery asset because no active session GUID is available: "
          "${asset.id}",
        );
        skippedMediaCount += 1;
        continue;
      }
      final photosBefore =
          SessionManager.instance.currentSession?.capturedPhotos.length ?? 0;
      final videosBefore =
          SessionManager.instance.currentSession?.capturedVideos.length ?? 0;
      try {
        await widget.galleryAttachmentService.attachImportedMedia(
          sourceFile: file,
          sessionGuid: sessionGuid,
          assetId: asset.id,
          assetType: asset.type,
          createDateTime: asset.createDateTime,
          videoDuration: asset.videoDuration,
          deviceId: deviceId,
        );
      } catch (error) {
        LogService.instance.registerLog(
          "Failed to import selected gallery asset ${asset.id}: $error",
        );
        skippedMediaCount += 1;
        continue;
      }
      final photosAfter =
          SessionManager.instance.currentSession?.capturedPhotos.length ?? 0;
      final videosAfter =
          SessionManager.instance.currentSession?.capturedVideos.length ?? 0;
      if (photosAfter > photosBefore || videosAfter > videosBefore) {
        importedMediaCount += 1;
      } else {
        skippedMediaCount += 1;
      }
    }

    if (importedMediaCount > 0) {
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      SessionManager.instance.notifyListeners();
    } else {
      LogService.instance.registerLog(
        "No selected gallery media was imported into the active session.",
      );
    }

    if (!mounted) return;

    final String message;
    if (importedMediaCount == 0) {
      message = "No gallery media was added";
    } else if (skippedMediaCount == 0) {
      message = "Media added to session";
    } else {
      final importedText = importedMediaCount == 1
          ? "1 gallery media item"
          : "$importedMediaCount gallery media items";
      final skippedText =
          skippedMediaCount == 1 ? "1 skipped" : "$skippedMediaCount skipped";
      message = "$importedText added, $skippedText";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool sessionActive = SessionManager.instance.isSessionActive;
    final bool isButtonEnabled = widget.enabled && sessionActive;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isButtonEnabled ? () => unawaited(_onPressed()) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isButtonEnabled ? null : AppTheme.disabledButtonColor,
        ),
        child: const Text(
          "Add Media from Gallery",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
