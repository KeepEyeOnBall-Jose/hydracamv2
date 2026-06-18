import "dart:async";
import "dart:io";
import "package:flutter/material.dart";
import "../app_theme.dart";
import "../models/capture_session.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../models/session_upload_state.dart";
import "../services/alert_utils.dart";
import "../services/session_manager.dart";
import "../services/uploader_service.dart";
import "../master/master_screen.dart";

class SessionDetailsScreen extends StatelessWidget {
  final CaptureSession session;
  final String? storageIdentifier;

  const SessionDetailsScreen({
    super.key,
    required this.session,
    this.storageIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final photos = session.capturedPhotos;
    final videos = session.capturedVideos;

    return Scaffold(
      appBar: AppBar(
        title: Text("Session: ${session.preferredIdentifier}"),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Session metadata
          _buildSessionMetadata(context),

          const Divider(),

          // Media list
          Expanded(
            child: ListView(
              children: [
                _buildMediaSection("Photos", photos, context),
                const Divider(),
                _buildMediaSection("Videos", videos, context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionMetadata(BuildContext context) {
    final hasBackendGuid =
        session.sessionGuid != null && session.sessionGuid!.isNotEmpty;
    final hasDistinctLegacySessionId =
        hasBackendGuid && session.sessionId != session.sessionGuid;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Session Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text("Session: ${session.preferredIdentifier}"),
                if (hasDistinctLegacySessionId)
                  Text("Legacy Session ID: ${session.sessionId}"),
                Text("Start Time: ${session.startTime}"),
                if (session.endTime != null)
                  Text("End Time: ${session.endTime}"),
                Text("Upload State: ${summarizeSessionUpload(session).label}"),
                Text("Total Photos: ${session.capturedPhotos.length}"),
                Text("Total Videos: ${session.capturedVideos.length}"),
                const SizedBox(height: 12),
                _buildPlayerAssignmentState(),
              ],
            ),
          ),
          // Compact button with icon
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.file_download_outlined,
                color: AppTheme.accent,
              ),
              tooltip: "Load Session",
              onPressed: () => unawaited(_loadSessionWithoutUploading(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerAssignmentState() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, size: 20),
              SizedBox(width: 8),
              Text(
                "Players",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Source: backend not configured"),
          const SizedBox(height: 4),
          const Text("Import source: waiting for session-player API"),
          const SizedBox(height: 4),
          const Text("Mid-session additions unavailable until FR-061 exists"),
          const SizedBox(height: 4),
          Text(
            "Player assignment unavailable",
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSessionWithoutUploading(BuildContext context) async {
    try {
      await SessionManager.instance.restoreSessionFromMetadata(
        storageIdentifier ?? session.preferredIdentifier,
        deviceType: "Master",
      );

      if (!context.mounted) return;

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session loaded successfully.")),
      );

      // Redirect to main page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MasterScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load session: $e")),
      );
    }
  }

  Widget _buildMediaSection(
      String title, List<dynamic> mediaList, BuildContext context) {
    if (mediaList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          "No $title in this session.",
          style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ...mediaList.map((media) {
          return _buildMediaItem(media, context);
        }),
      ],
    );
  }

  Widget _buildMediaItem(dynamic media, BuildContext context) {
    final isPhoto = media is CapturedPhoto;
    final title = isPhoto ? "Photo" : "Video";
    final path = media.mediaPath;
    final file = File(path);
    final fileExists = file.existsSync();
    final uploadStatus = media.isUploaded ? "Uploaded" : "Not Uploaded";
    final fileType = isPhoto ? "Photo" : "Video";

    return ListTile(
      leading: _buildMediaLeading(
          isPhoto: isPhoto, fileExists: fileExists, path: path),
      title: Text("$title from ${media.slaveDeviceId}"),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Path: $path"),
          Text("Status: $uploadStatus"),
          if (!fileExists)
            const Text(
              "Local file missing",
              style: TextStyle(color: AppTheme.danger),
            ),
        ],
      ),
      trailing: IconButton(
        icon: media.isUploaded
            ? const Icon(Icons.cloud_done, color: AppTheme.textPrimary)
            : const Icon(Icons.cloud_upload_outlined, color: AppTheme.danger),
        onPressed: () {
          if (!fileExists) {
            AlertUtils.showFileMissingDialog(fileType, context);
          } else if (media.isUploaded) {
            // Show info alert for already uploaded media
            AlertUtils.showUploadedMediaAlert(context, path);
          } else {
            // Ask to load session and upload all unsent media
            AlertUtils.showUploadAllMediaAlert(
              context,
              () => unawaited(_loadSessionAndUploadMedia(context)),
            );
          }
        },
      ),
      onTap: () {
        if (!fileExists) {
          AlertUtils.showFileMissingDialog(fileType, context);
        } else if (isPhoto) {
          _showPhotoDialog(context, media);
        } else {
          _showVideoDialog(context, media);
        }
      },
    );
  }

  Widget _buildMediaLeading({
    required bool isPhoto,
    required bool fileExists,
    required String path,
  }) {
    if (isPhoto && fileExists) {
      return Image.file(File(path), width: 50, height: 50, fit: BoxFit.cover);
    }
    if (isPhoto) {
      return const Icon(Icons.broken_image_outlined,
          size: 50, color: AppTheme.danger);
    }
    return const Icon(Icons.videocam, size: 50, color: AppTheme.accent);
  }

  void _showPhotoDialog(BuildContext context, CapturedPhoto photo) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Image.file(File(photo.photoPath)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showVideoDialog(BuildContext context, CapturedVideo video) {
    AlertUtils.showMediaDialog(
      context: context,
      media: video,
      isAutoCloseEnabled: false,
    );
  }

  Future<void> _loadSessionAndUploadMedia(BuildContext context) async {
    try {
      await SessionManager.instance.restoreSessionFromMetadata(
        session.preferredIdentifier,
        deviceType: "Master",
      );

      if (!context.mounted) return;

      // Notify user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("Session loaded and unsent media added to upload queue.")),
      );

      // Navigate to the Master screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MasterScreen()),
      );

      // Init upload process
      await UploaderService().startUploadingManually();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load session: $e")),
      );
    }
  }
}
