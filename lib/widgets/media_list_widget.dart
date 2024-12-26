import 'package:flutter/material.dart';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import '../services/uploader_service.dart';
import 'dart:io';

/// Reusable widget to show list of recorded photos and videos for a device (both slave or master)
/// Used both in uploader screen and master/slave screens, with different functionalities in each case
class MediaListWidget extends StatelessWidget {
  final List<CapturedPhoto> photos;
  final List<CapturedVideo> videos;
  final Function(CapturedPhoto)? onPhotoTap;
  final Function(CapturedVideo)? onVideoTap;
  final Function(CapturedPhoto)? onRetryPhotoUpload;
  final Function(CapturedVideo)? onRetryVideoUpload;
  final bool showPlaceholder; // Show or not a placeholder image and text if there is still no media

  /// Constructor
  const MediaListWidget({
    Key? key,
    required this.photos,
    required this.videos,
    this.onPhotoTap,
    this.onVideoTap,
    this.onRetryPhotoUpload,
    this.onRetryVideoUpload,
    this.showPlaceholder = false
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final totalItems = photos.length + videos.length;

    // Show placeholder if enabled and there are no media items
    if (showPlaceholder && totalItems == 0) {
      return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.perm_media_outlined, // Multimedia icon
                size: 100, // Adjust the size as needed
                color: Colors.grey, // Set the icon color
              ),
              SizedBox(height: 20),
              Text(
                "No media available",
                style: TextStyle(
                  fontSize: 18, // Text size
                  color: Colors.grey, // Text color
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                "Photos and videos will appear here once captured.",
                style: TextStyle(
                  fontSize: 14, // Smaller text size
                  color: Colors.grey, // Text color
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Else, proceed normally...
    // Build the list of media items
    return ListView.builder(
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < photos.length) {
          final photo = photos[index];
          return ValueListenableBuilder<dynamic>(
            valueListenable: UploaderService().currentlyUploadingNotifier,
            builder: (context, currentlyUploading, _) {
              return ListTile(
                leading: Image.file(File(photo.photoPath), width: 50, height: 50),
                title: Text("Photo from: ${photo.slaveDeviceId}"),
                subtitle: Text("Captured: ${photo.captureDate}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadIcon(photo, currentlyUploading),
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
            },
          );
        } else {
          final video = videos[index - photos.length];
          return ValueListenableBuilder<dynamic>(
            valueListenable: UploaderService().currentlyUploadingNotifier,
            builder: (context, currentlyUploading, _) {
              return ListTile(
                leading: const Icon(Icons.videocam, size: 50),
                title: Text("Video from: ${video.slaveDeviceId}"),
                subtitle: Text("Started: ${video.startRecordingDate}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadIcon(video, currentlyUploading),
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
            },
          );
        }
      },
    );
  }

  /// Builds the upload icon dynamically based on the upload state.
  Widget _buildUploadIcon(dynamic media, dynamic currentlyUploading) {
    if (media == currentlyUploading) {
      // Show circular progress with percentage
      return ValueListenableBuilder<double>(
        valueListenable: UploaderService().uploadProgressNotifier,
        builder: (context, progress, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress, // Progress from 0.0 to 1.0
                strokeWidth: 2,
                color: Colors.blue,
              ),
              Text(
                "${(progress * 100).toInt()}%", // Percentage text
                style: const TextStyle(fontSize: 10, color: Colors.black),
              ),
            ],
          );
        },
      );
    } else if (media.isUploaded) {
      // Already uploaded
      return const Icon(Icons.cloud_done, color: Colors.blue);
    } else {
      // Not uploaded yet
      return const Icon(Icons.cloud_upload, color: Colors.black);
    }
  }
}
