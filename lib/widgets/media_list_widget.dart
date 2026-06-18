import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "../app_theme.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/uploader_service.dart";

/// Reusable widget to show list of recorded photos and videos for a device (both slave or master)
/// Used both in uploader screen and master/slave screens, with different functionalities in each case
class MediaListWidget extends StatelessWidget {
  final List<CapturedPhoto> photos;
  final List<CapturedVideo> videos;
  final Function(CapturedPhoto)? onPhotoTap;
  final Function(CapturedVideo)? onVideoTap;
  final Function(CapturedPhoto)? onRetryPhotoUpload;
  final Function(CapturedVideo)? onRetryVideoUpload;
  final FutureOr<void> Function(CapturedPhoto)? onCancelPhotoUpload;
  final FutureOr<void> Function(CapturedVideo)? onCancelVideoUpload;
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
      return SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.perm_media_outlined, // Multimedia icon
                size: 100, // Adjust the size as needed
                color: AppTheme.textTertiary,
              ),
              SizedBox(height: 20),
              Text(
                "No media available",
                style: TextStyle(
                  fontSize: 18, // Text size
                  color: AppTheme.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                "Photos and videos will appear here once captured.",
                style: TextStyle(
                  fontSize: 14, // Smaller text size
                  color: AppTheme.textSecondary,
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
              final missingLocalFile =
                  _isLocalFileMissing(photo, currentlyUploading);
              return ListTile(
                leading: _buildPhotoLeading(photo, missingLocalFile),
                title: Text("Photo from: ${photo.slaveDeviceId}"),
                subtitle: _buildSubtitle(
                  primary: "Captured: ${photo.captureDate}",
                  media: photo,
                  currentlyUploading: currentlyUploading,
                  missingLocalFile: missingLocalFile,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadStatusIndicator(
                      photo,
                      currentlyUploading,
                      missingLocalFile: missingLocalFile,
                    ),
                    if (!missingLocalFile &&
                        !_isCurrentUpload(photo, currentlyUploading) &&
                        !photo.isUploaded &&
                        onRetryPhotoUpload != null)
                      IconButton(
                        tooltip: _uploadActionTooltip(
                          photo,
                          currentlyUploading,
                        ),
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.accent,
                        ),
                        onPressed: () {
                          onRetryPhotoUpload!(photo);
                        },
                      ),
                    if (!missingLocalFile &&
                        _canCancelUpload(photo, currentlyUploading) &&
                        onCancelPhotoUpload != null)
                      IconButton(
                        tooltip: "Cancel upload",
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: AppTheme.danger,
                        ),
                        onPressed: () async {
                          await onCancelPhotoUpload!(photo);
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
              final missingLocalFile =
                  _isLocalFileMissing(video, currentlyUploading);
              return ListTile(
                leading: _buildVideoLeading(missingLocalFile),
                title: Text("Video from: ${video.slaveDeviceId}"),
                subtitle: _buildSubtitle(
                  primary: "Started: ${video.startRecordingDate}",
                  media: video,
                  currentlyUploading: currentlyUploading,
                  missingLocalFile: missingLocalFile,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildUploadStatusIndicator(
                      video,
                      currentlyUploading,
                      missingLocalFile: missingLocalFile,
                    ),
                    if (!missingLocalFile &&
                        !_isCurrentUpload(video, currentlyUploading) &&
                        !video.isUploaded &&
                        onRetryVideoUpload != null)
                      IconButton(
                        tooltip: _uploadActionTooltip(
                          video,
                          currentlyUploading,
                        ),
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.accent,
                        ),
                        onPressed: () {
                          onRetryVideoUpload!(video);
                        },
                      ),
                    if (!missingLocalFile &&
                        _canCancelUpload(video, currentlyUploading) &&
                        onCancelVideoUpload != null)
                      IconButton(
                        tooltip: "Cancel upload",
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: AppTheme.danger,
                        ),
                        onPressed: () async {
                          await onCancelVideoUpload!(video);
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
    dynamic media,
    dynamic currentlyUploading, {
    required bool missingLocalFile,
  }) {
    if (missingLocalFile) {
      return _buildStatusPill(
        icon: Icons.error_outline,
        label: "Missing",
        semanticsLabel: "Upload status: Local file missing",
        foregroundColor: AppTheme.danger,
        backgroundColor: AppTheme.dangerSurface,
        borderColor: AppTheme.danger,
      );
    }

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
                        color: AppTheme.accent,
                      ),
                      Text(
                        "${(progress * 100).toInt()}%", // Percentage text
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatByteProgress(media, progress),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textPrimary,
                    ),
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
        foregroundColor: AppTheme.textPrimary,
        backgroundColor: AppTheme.surfaceMuted,
        borderColor: AppTheme.border,
      );
    } else if (_hasUploadFailed(media, currentlyUploading)) {
      final uploadFailureReason = _uploadFailureReason(media);
      return _buildStatusPill(
        icon: Icons.error_outline,
        label: "Failed",
        semanticsLabel: uploadFailureReason == null
            ? "Upload status: Upload failed"
            : "Upload status: $uploadFailureReason",
        foregroundColor: AppTheme.danger,
        backgroundColor: AppTheme.dangerSurface,
        borderColor: AppTheme.danger,
      );
    } else {
      return _buildStatusPill(
        icon: Icons.cloud_upload_outlined,
        label: "Pending",
        semanticsLabel: "Upload status: Pending upload",
        foregroundColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surfaceMuted,
        borderColor: AppTheme.border,
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
    required bool missingLocalFile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(primary),
        Text(
          _uploadStatusLabel(
            media,
            currentlyUploading,
            missingLocalFile: missingLocalFile,
          ),
          style: TextStyle(
            color:
                missingLocalFile || _hasUploadFailed(media, currentlyUploading)
                    ? AppTheme.danger
                    : AppTheme.textSecondary,
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
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              );
            },
          ),
      ],
    );
  }

  String _uploadStatusLabel(
    dynamic media,
    dynamic currentlyUploading, {
    required bool missingLocalFile,
  }) {
    if (missingLocalFile) {
      return "Local file missing";
    }
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

  Widget _buildPhotoLeading(CapturedPhoto photo, bool missingLocalFile) {
    if (missingLocalFile) {
      return _buildMissingLocalFileLeading(Icons.broken_image_outlined);
    }
    return Image.file(
      File(photo.photoPath),
      width: 50,
      height: 50,
      fit: BoxFit.cover,
    );
  }

  Widget _buildVideoLeading(bool missingLocalFile) {
    if (missingLocalFile) {
      return _buildMissingLocalFileLeading(Icons.videocam_off);
    }
    return const Icon(Icons.videocam, size: 50);
  }

  Widget _buildMissingLocalFileLeading(IconData icon) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.dangerSurface,
        border: Border.all(color: AppTheme.danger),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: AppTheme.danger,
        size: 28,
      ),
    );
  }

  bool _isLocalFileMissing(dynamic media, dynamic currentlyUploading) {
    if (_isCurrentUpload(media, currentlyUploading) || media.isUploaded) {
      return false;
    }

    try {
      return !File(media.mediaPath as String).existsSync();
    } catch (_) {
      return true;
    }
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
