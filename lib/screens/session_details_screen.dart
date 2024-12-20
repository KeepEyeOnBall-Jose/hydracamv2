import 'dart:io';
import 'package:flutter/material.dart';
import '../models/CaptureSession.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/alert_utils.dart';
import '../services/session_manager.dart';
import '../services/uploader_service.dart';
import 'master_screen.dart';

class SessionDetailsScreen extends StatelessWidget {
  final CaptureSession session;

  const SessionDetailsScreen({Key? key, required this.session}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final photos = session.capturedPhotos;
    final videos = session.capturedVideos;

    return Scaffold(
      appBar: AppBar(
        title: Text("Session: ${session.sessionId}"),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Session metadata
          _buildSessionMetadata(),

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

  Widget _buildSessionMetadata() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Session Details",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text("Session ID: ${session.sessionId}"),
          Text("Session GUID: ${session.sessionGuid ?? 'Unavailable'}"),
          Text("Start Time: ${session.startTime}"),
          if (session.endTime != null) Text("End Time: ${session.endTime}"),
          Text("Total Photos: ${session.capturedPhotos.length}"),
          Text("Total Videos: ${session.capturedVideos.length}"),
        ],
      ),
    );
  }

  Widget _buildMediaSection(String title, List<dynamic> mediaList, BuildContext context) {
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
        }).toList(),
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
              context,() => _loadSessionAndUploadMedia(context),
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


  // TODO: Extract from here
  void _loadSessionAndUploadMedia(BuildContext context) async {
    try {
      // Load session
      print("Try to load session. Is session != null : ${session != null}");
      print("Is guid != null: ${session.sessionGuid != null}");

      SessionManager.instance.startSession(session.sessionGuid!, null, deviceType: "Master"); // TODO: Master or the previous one??

      final loadedSession = await SessionManager.instance.loadSessionMetadata(session.sessionGuid!);

      if (loadedSession == null) {
        throw Exception("Failed to load session metadata for GUID: ${session.sessionGuid!}");
      }

      for (final photo in loadedSession.capturedPhotos) {
        SessionManager.instance.addPhoto(photo);
      }
      for (final video in loadedSession.capturedVideos) {
        SessionManager.instance.addVideo(video);
      }

      // Notify user
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session loaded and unsent media added to upload queue.")),
      );

      // Navigate to the Master screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MasterScreen()),
      );


      // Init upload process
      UploaderService().startUploadingManually();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load session: $e")),
      );
    }
  }

}
