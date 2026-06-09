import "dart:async";
import "dart:io";
import "package:flutter/material.dart";
import "../models/capture_session.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/alert_utils.dart";
import "../services/session_manager.dart";
import "../services/uploader_service.dart";
import "../master/master_screen.dart";

class SessionDetailsScreen extends StatelessWidget {
  final CaptureSession session;

  const SessionDetailsScreen({super.key, required this.session});

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
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon:
                  const Icon(Icons.file_download_outlined, color: Colors.blue),
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
        border: Border.all(color: Colors.grey.shade300),
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
          Text(
            "Player assignment unavailable",
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSessionWithoutUploading(BuildContext context) async {
    try {
      await SessionManager.instance.restoreSessionFromMetadata(
        session.preferredIdentifier,
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
          style: const TextStyle(fontSize: 16, color: Colors.grey),
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
    final uploadStatus = media.isUploaded ? "Uploaded" : "Not Uploaded";

    return ListTile(
      leading: isPhoto
          ? Image.file(File(path), width: 50, height: 50, fit: BoxFit.cover)
          : const Icon(Icons.videocam, size: 50, color: Colors.blue),
      title: Text("$title from ${media.slaveDeviceId}"),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Path: $path"),
          Text("Status: $uploadStatus"),
        ],
      ),
      trailing: IconButton(
        icon: media.isUploaded
            ? const Icon(Icons.cloud_done, color: Colors.blue)
            : const Icon(Icons.cloud_upload_outlined, color: Colors.red),
        onPressed: () {
          if (media.isUploaded) {
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
        if (isPhoto) {
          _showPhotoDialog(context, media);
        } else {
          _showVideoDialog(context, media);
        }
      },
    );
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
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: const Text("Video playback is not implemented yet."),
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
