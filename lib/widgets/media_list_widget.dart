import 'package:flutter/material.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'dart:io';

/// Reusable widget to show list of recorded photos and videos for a device (both slave or master)
class MediaListWidget extends StatelessWidget {
  final List<CapturedPhoto> photos;
  final List<CapturedVideo> videos;
  final Function(CapturedPhoto)? onPhotoTap;
  final Function(CapturedVideo)? onVideoTap;

  final Function(CapturedPhoto)? onRetryPhotoUpload;
  final Function(CapturedVideo)? onRetryVideoUpload;

  /// Constructor
  const MediaListWidget({
    Key? key,
    required this.photos,
    required this.videos,
    this.onPhotoTap,
    this.onVideoTap,
    this.onRetryPhotoUpload,
    this.onRetryVideoUpload,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final totalItems = photos.length + videos.length;

    return ListView.builder(
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < photos.length) {
          final photo = photos[index];
          return ListTile(
            leading: Image.file(File(photo.photoPath), width: 50, height: 50),
            title: Text("Photo from: ${photo.slaveDeviceId}"),
            subtitle: Text("Captured: ${photo.captureDate}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload,
                  color: photo.isUploaded ? Colors.blue : Colors.black,
                ),
                if (!photo.isUploaded && onRetryPhotoUpload != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.green),
                    onPressed: () {
                      onRetryPhotoUpload!(photo);
                    },
                  ),
              ],
            ),
            onTap: () {
              if (onPhotoTap != null) {
                onPhotoTap!(photo);
              }
            },
          );
        } else {
          final video = videos[index - photos.length];
          return ListTile(
            leading: const Icon(Icons.videocam, size: 50),
            title: Text("Video from: ${video.slaveDeviceId}"),
            subtitle: Text("Started: ${video.startRecordingDate}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload,
                  color: video.isUploaded ? Colors.blue : Colors.black,
                ),
                if (!video.isUploaded && onRetryVideoUpload != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.green),
                    onPressed: () {
                      onRetryVideoUpload!(video);
                    },
                  ),
              ],
            ),
            onTap: () {
              if (onVideoTap != null) {
                onVideoTap!(video);
              }
            },
          );
        }
      },
    );
  }
}
