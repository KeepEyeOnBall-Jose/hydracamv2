import 'package:flutter/material.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/session_manager.dart';
import '../widgets/media_list_widget.dart';

/// Screen available from appbar menu that shows current session related media and their upload status
class UploaderInfoScreen extends StatelessWidget {
  const UploaderInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    List<CapturedPhoto> photos = SessionManager.instance.currentSession?.capturedPhotos ?? [];
    List<CapturedVideo> videos = SessionManager.instance.currentSession?.capturedVideos ?? [];

    int uploadedPhotos = photos.where((p) => p.isUploaded).length;
    int totalPhotos = photos.length;

    int uploadedVideos = videos.where((v) => v.isUploaded).length;
    int totalVideos = videos.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploader Info'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Photos uploaded: $uploadedPhotos / $totalPhotos', style: TextStyle(fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Videos uploaded: $uploadedVideos / $totalVideos', style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: MediaListWidget(
              photos: photos,
              videos: videos,
              // Optionally customize onTap callbacks
            ),
          ),
        ],
      ),
    );
  }
}
