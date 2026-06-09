import "package:flutter/material.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/uploader_service.dart";
import "dart:io";

/// Reusable widget to show list of recorded photos and videos for a device (both slave or master)
/// Used both in uploader screen and master/slave screens, with different functionalities in each case
class MediaListWidget extends StatelessWidget {
  final List<CapturedPhoto> photos;
  final List<CapturedVideo> videos;
  final Function(CapturedPhoto)? onPhotoTap;
  final Function(CapturedVideo)? onVideoTap;
  final Function(CapturedPhoto)? onRetryPhotoUpload;
  final Function(CapturedVideo)? onRetryVideoUpload;
  final Function(CapturedPhoto)? onCancelPhotoUpload;
  final Function(CapturedVideo)? onCancelVideoUpload;
  final DateTime Function()? now;
  final bool
      showPlaceholder; // Show or not a placeholder image and text if there is still no media

  /// Constructor
  const MediaListWidget(
      {super.key,
      required this.photos,
      required this.videos,
      this.onPhotoTap,
      this.onVideoTap,
      this.onRetryPhotoUpload,
      this.onRetryVideoUpload,
      this.onCancelPhotoUpload,
      this.onCancelVideoUpload,
      this.now,
      this.showPlaceholder = false});

  @override
  Widget build(BuildContext context) {
    final totalItems = photos.length + videos.length;

    // Show placeholder if enabled and there are no media items
    if (showPlaceholder && totalItems == 0) {
      return const SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                leading:
                    Image.file(File(photo.photoPath), width: 50, height: 50),
                title: Text("Photo from: ${photo.slaveDeviceId}"),
                subtitle: _buildSubtitle(
                  primary: "Captured: ${photo.captureDate}",
                  media: photo,
                  currentlyUploading: currentlyUploading,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadStatusIndicator(photo, currentlyUploading),
                    if (!_isCurrentUpload(photo, currentlyUploading) &&
                        !photo.isUploaded &&
                        onRetryPhotoUpload != null)
                      IconButton(
                        tooltip: _uploadActionTooltip(
                          photo,
                          currentlyUploading,
                        ),
                        icon: const Icon(Icons.refresh, color: Colors.green),
                        onPressed: () {
                          onRetryPhotoUpload!(photo);
                        },
                      ),
                    if (_canCancelUpload(photo, currentlyUploading) &&
                        onCancelPhotoUpload != null)
                      IconButton(
                        tooltip: "Cancel upload",
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.orange),
                        onPressed: () {
                          onCancelPhotoUpload!(photo);
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
                subtitle: _buildSubtitle(
                  primary: "Started: ${video.startRecordingDate}",
                  media: video,
                  currentlyUploading: currentlyUploading,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadStatusIndicator(video, currentlyUploading),
                    if (!_isCurrentUpload(video, currentlyUploading) &&
                        !video.isUploaded &&
                        onRetryVideoUpload != null)
                      IconButton(
                        tooltip: _uploadActionTooltip(
                          video,
                          currentlyUploading,
                        ),
                        icon: const Icon(Icons.refresh, color: Colors.green),
                        onPressed: () {
                          onRetryVideoUpload!(video);
                        },
                      ),
                    if (_canCancelUpload(video, currentlyUploading) &&
                        onCancelVideoUpload != null)
                      IconButton(
                        tooltip: "Cancel upload",
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.orange),
                        onPressed: () {
                          onCancelVideoUpload!(video);
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

  /// Builds a non-interactive upload status indicator.
  Widget _buildUploadStatusIndicator(
      dynamic media, dynamic currentlyUploading) {
    if (media == currentlyUploading) {
      // Show circular progress with percentage
      return Semantics(
        container: true,
        label: "Upload status: Uploading",
        child: ExcludeSemantics(
          child: ValueListenableBuilder<double>(
            valueListenable: UploaderService().uploadProgressNotifier,
            builder: (context, progress, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress, // Progress from 0.0 to 1.0
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                      Text(
                        "${(progress * 100).toInt()}%", // Percentage text
                        style:
                            const TextStyle(fontSize: 10, color: Colors.black),
                      ),
                    ],
                  ),
                  Text(
                    _formatByteProgress(media, progress),
                    style: const TextStyle(fontSize: 10, color: Colors.black),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } else if (media.isUploaded) {
      return _buildStatusPill(
        icon: Icons.cloud_done,
        label: "Uploaded",
        semanticsLabel: "Upload status: Uploaded",
        foregroundColor: Colors.blue.shade700,
        backgroundColor: Colors.blue.shade50,
        borderColor: Colors.blue.shade200,
      );
    } else if (_hasUploadFailed(media, currentlyUploading)) {
      final uploadFailureReason = _uploadFailureReason(media);
      return _buildStatusPill(
        icon: Icons.error_outline,
        label: "Failed",
        semanticsLabel: uploadFailureReason == null
            ? "Upload status: Upload failed"
            : "Upload status: $uploadFailureReason",
        foregroundColor: Colors.red.shade700,
        backgroundColor: Colors.red.shade50,
        borderColor: Colors.red.shade200,
      );
    } else {
      return _buildStatusPill(
        icon: Icons.cloud_upload_outlined,
        label: "Pending",
        semanticsLabel: "Upload status: Pending upload",
        foregroundColor: Colors.grey.shade800,
        backgroundColor: Colors.grey.shade100,
        borderColor: Colors.grey.shade300,
      );
    }
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required Color foregroundColor,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 82),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle({
    required String primary,
    required dynamic media,
    required dynamic currentlyUploading,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(primary),
        Text(
          _uploadStatusLabel(media, currentlyUploading),
          style: TextStyle(
            color: _hasUploadFailed(media, currentlyUploading)
                ? Colors.red
                : Colors.grey.shade700,
            fontSize: 12,
          ),
        ),
        if (media == currentlyUploading)
          ValueListenableBuilder<double>(
            valueListenable: UploaderService().uploadProgressNotifier,
            builder: (context, progress, _) {
              final timeRemaining = _formatUploadTimeRemaining(
                media,
                progress,
              );
              if (timeRemaining == null) {
                return const SizedBox.shrink();
              }
              return Text(
                timeRemaining,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              );
            },
          ),
      ],
    );
  }

  String _uploadStatusLabel(dynamic media, dynamic currentlyUploading) {
    if (media == currentlyUploading) {
      return "Uploading";
    }
    if (media.isUploaded) {
      return "Uploaded";
    }
    if (_hasUploadFailed(media, currentlyUploading)) {
      return _uploadFailureReason(media) ?? "Upload failed";
    }
    return "Pending upload";
  }

  bool _hasUploadFailed(dynamic media, dynamic currentlyUploading) {
    return media != currentlyUploading &&
        media.isUploaded == false &&
        (media.uploadStartTime != null || _uploadFailureReason(media) != null);
  }

  String? _uploadFailureReason(dynamic media) {
    final reason = media.uploadFailureReason as String?;
    if (reason == null || reason.trim().isEmpty) {
      return null;
    }
    return reason;
  }

  bool _canCancelUpload(dynamic media, dynamic currentlyUploading) {
    if (_isCurrentUpload(media, currentlyUploading)) {
      return true;
    }
    return media.isUploaded == false && media.uploadStartTime == null;
  }

  bool _isCurrentUpload(dynamic media, dynamic currentlyUploading) {
    return media == currentlyUploading;
  }

  String _uploadActionTooltip(dynamic media, dynamic currentlyUploading) {
    if (_hasUploadFailed(media, currentlyUploading)) {
      return "Retry upload";
    }
    return "Queue upload";
  }

  String _formatByteProgress(dynamic media, double progress) {
    final totalBytes = media.fileSizeInBytes as int;
    final uploadedBytes = (totalBytes * progress.clamp(0.0, 1.0)).round();
    return "${_formatBytes(uploadedBytes)} / ${_formatBytes(totalBytes)}";
  }

  String? _formatUploadTimeRemaining(dynamic media, double progress) {
    final uploadStartTime = media.uploadStartTime as DateTime?;
    final progressValue = progress.clamp(0.0, 1.0).toDouble();
    if (uploadStartTime == null || progressValue <= 0 || progressValue >= 1) {
      return null;
    }

    final elapsed = (now?.call() ?? DateTime.now()).difference(uploadStartTime);
    if (elapsed.inMilliseconds <= 0) {
      return null;
    }

    final estimatedTotalMs = elapsed.inMilliseconds / progressValue;
    final remainingMs = (estimatedTotalMs - elapsed.inMilliseconds).round();
    if (remainingMs <= 0) {
      return null;
    }

    return "About ${_formatRemainingDuration(Duration(milliseconds: remainingMs))} left";
  }

  String _formatRemainingDuration(Duration duration) {
    final seconds = (duration.inMilliseconds / 1000).ceil();
    if (seconds < 60) {
      return "${seconds}s";
    }

    final minutes = (seconds / 60).ceil();
    if (minutes < 60) {
      return "${minutes}m";
    }

    final hours = (minutes / 60).ceil();
    return "${hours}h";
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return "$bytes B";
    }

    final kib = bytes / 1024;
    if (kib < 1024) {
      return "${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KB";
    }

    final mib = kib / 1024;
    return "${mib.toStringAsFixed(mib >= 10 ? 0 : 1)} MB";
  }
}
