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

  const MediaListWidget({
    Key? key,
    required this.photos,
    required this.videos,
    this.onPhotoTap,
    this.onVideoTap,
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
            trailing: Icon(
              Icons.cloud_upload,
              color: photo.isUploaded ? Colors.blue : Colors.black,
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
            trailing: Icon(
              Icons.cloud_upload,
              color: video.isUploaded ? Colors.blue : Colors.black,
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
