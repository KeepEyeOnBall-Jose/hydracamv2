import "package:flutter/material.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "../services/session_manager.dart";
import "../services/uploader_service.dart";
import "../widgets/media_list_widget.dart";

/// Screen available from appbar menu that shows current session related media and their upload status
class UploaderInfoScreen extends StatefulWidget {
  const UploaderInfoScreen({super.key});

  @override
  State<UploaderInfoScreen> createState() => _UploaderInfoScreenState();
}

class _UploaderInfoScreenState extends State<UploaderInfoScreen> {
  bool _isStartingUploads = false;

  Future<void> _cancelUpload(dynamic media) async {
    final cancelled = await UploaderService().cancelMediaUpload(media);
    if (!mounted) {
      return;
    }
    if (cancelled) {
      setState(() {});
    }
  }

  Future<void> _startUploads() async {
    if (_isStartingUploads) {
      return;
    }
    setState(() {
      _isStartingUploads = true;
    });
    try {
      await UploaderService().startUploadingManually();
    } finally {
      if (mounted) {
        setState(() {
          _isStartingUploads = false;
        });
      }
    }
  }

  String _mediaFileName(dynamic media) {
    final mediaPath = media.mediaPath.toString().replaceAll("\\", "/");
    return mediaPath.split("/").last;
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) {
      return "0s";
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes == 0) {
      return "${seconds}s";
    }
    return "${minutes}m ${seconds}s";
  }

  String _formatEstimatedRemaining(Duration duration, dynamic currentUpload) {
    if (currentUpload != null && duration == Duration.zero) {
      return "calculating";
    }
    return _formatDuration(duration);
  }

  @override
  Widget build(BuildContext context) {
    final List<CapturedPhoto> photos =
        SessionManager.instance.currentSession?.capturedPhotos ?? [];
    final List<CapturedVideo> videos =
        SessionManager.instance.currentSession?.capturedVideos ?? [];

    final int uploadedPhotos = photos.where((p) => p.isUploaded).length;
    final int totalPhotos = photos.length;

    final int uploadedVideos = videos.where((v) => v.isUploaded).length;
    final int totalVideos = videos.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Uploader Info"),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<Duration>(
              valueListenable: UploaderService().estimatedTimeNotifier,
              builder: (context, estimatedTime, _) {
                return ValueListenableBuilder<dynamic>(
                  valueListenable: UploaderService().currentlyUploadingNotifier,
                  builder: (context, currentUpload, _) {
                    final currentUploadLabel = currentUpload == null
                        ? "none"
                        : _mediaFileName(currentUpload);
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          Text(
                            "Photos uploaded: $uploadedPhotos / $totalPhotos",
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Videos uploaded: $uploadedVideos / $totalVideos",
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Queue: ${UploaderService().queueLength} pending",
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Current upload: $currentUploadLabel",
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            "Estimated remaining: ${_formatEstimatedRemaining(estimatedTime, currentUpload)}",
                            style: const TextStyle(fontSize: 16),
                          ),
                          ElevatedButton.icon(
                            icon: _isStartingUploads
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined),
                            label: Text(_isStartingUploads
                                ? "Starting uploads"
                                : "Start Uploads"),
                            onPressed: UploaderService().queueLength == 0 ||
                                    _isStartingUploads
                                ? null
                                : _startUploads,
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
          Expanded(
            child: MediaListWidget(
              photos: photos,
              videos: videos,
              onRetryPhotoUpload: (photo) async {
                await UploaderService().addMediaToQueue(photo);
                await UploaderService()
                    .startUploadingManually(); // Force manual upload
              },
              onRetryVideoUpload: (video) async {
                await UploaderService().addMediaToQueue(video);
                await UploaderService()
                    .startUploadingManually(); // Force manual upload
              },
              onCancelPhotoUpload: _cancelUpload,
              onCancelVideoUpload: _cancelUpload,
            ),
          ),
        ],
      ),
    );
  }
}
