import 'dart:collection';
import 'dart:io';
import 'package:flutter/cupertino.dart';

import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
import 'hydracam_api_service.dart';
import 'session_manager.dart';
import 'log_service.dart';

/// Singleton Module that manages the upload process of every media file recorded
class UploaderService {
  // Singleton pattern
  static final UploaderService _instance = UploaderService._internal();
  factory UploaderService() => _instance;
  UploaderService._internal();

  final Queue<dynamic> _uploadQueue = Queue();
  bool _isUploading = false;

  final ValueNotifier<Duration> estimatedTimeNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<dynamic> currentlyUploadingNotifier = ValueNotifier(null);

  // Reference to the API service
  final HydraCamApiService _apiService = HydraCamApiService();

  void addMediaToQueue(dynamic media) {
    if (media is CapturedPhoto || media is CapturedVideo) {
      _uploadQueue.add(media);
      LogService.instance.registerLog("Media added to upload queue: ${media.mediaPath}");
      _startUploading();
    } else {
      LogService.instance.registerLog("Invalid media type added to upload queue");
    }
  }

  void _startUploading() {
    LogService.instance.registerLog("UploaderService: _startUploading called. _isUploading=$_isUploading, queue length=${_uploadQueue.length}");
    if (!_isUploading && _uploadQueue.isNotEmpty) {
      _processNextItem();
    }
  }

  /// Processes next item of the queue. Uploads it, notifies possible error, and triggers local file deletion.
  void _processNextItem() async {
    LogService.instance.registerLog("UploaderService: _processNextItem called. Queue length=${_uploadQueue.length}");

    // Check if there is anything in the queue
    if (_uploadQueue.isEmpty) {
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      estimatedTimeNotifier.value = Duration.zero;
      LogService.instance.registerLog("UploaderService: Queue is empty. Uploading stopped.");
      return;
    }

    _isUploading = true;
    final media = _uploadQueue.removeFirst();
    currentlyUploadingNotifier.value = media;

    // Set upload start time
    media.uploadStartTime = DateTime.now();

    bool success = false;

    // Get session GUID
    String? sessionGuid = SessionManager.instance.sessionGuid;
    LogService.instance.registerLog("UploaderService: sessionGuid=$sessionGuid");

    if (sessionGuid == null) {
      LogService.instance.registerLog("No session GUID available. Cannot upload media.");
      // Set media as not uploaded
      media.isUploaded = false;
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      return;
    }

    // Prepare file
    File file = File(media.mediaPath);

    // Check if file exists
    if (!file.existsSync()) {
      LogService.instance.registerLog("UploaderService: File does not exist: ${file.path}");
      media.isUploaded = false;
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      _processNextItem();
      return;
    }

    // Prepare metadata
    String slaveDeviceId;
    DateTime captureDate;
    DateTime receivedDate;

    if (media is CapturedPhoto) {
      slaveDeviceId = media.slaveDeviceId;
      captureDate = media.captureDate;
      receivedDate = media.receivedDate;

      success = await _apiService.uploadMedia(
        sessionGuid,
        file,
        true, // isPhoto
        slaveDeviceId,
        captureDate,
        receivedDate,
      );

    } else if (media is CapturedVideo) {
      slaveDeviceId = media.slaveDeviceId;
      captureDate = media.startRecordingDate;
      receivedDate = media.receivedDate;
      success = await _apiService.uploadMedia(
        sessionGuid,
        file,
        false, // isPhoto
        slaveDeviceId,
        captureDate,
        receivedDate,
      );
    }

    if (success) {
      // Update metadata and register log
      media.isUploaded = true;
      media.uploadDuration = DateTime.now().difference(media.uploadStartTime!);
      LogService.instance.registerLog("Media uploaded: ${media.mediaPath}");
      // Trigger deletion of the local file
      await SessionManager.instance.deleteFileIfAllowed(media.mediaPath);

    } else {
      media.isUploaded = false;
      LogService.instance.registerLog("Failed to upload media: ${media.mediaPath}");
    }

    // Notify listeners to update UI
    SessionManager.instance.notifyListeners();
    currentlyUploadingNotifier.value = null;

    // Recalculate estimated time
    estimatedTimeNotifier.value = estimateTotalTimeRemaining();

    // Process next item
    _processNextItem();
  }

  bool get isUploading => _isUploading;

  int get queueLength => _uploadQueue.length;

  /// Estimates the time remaining to upload all files in the queue based on past uploads.
  Duration estimateTotalTimeRemaining() {
    //TODO WIP
    // If queue empty there is no estimated time
    if (_uploadQueue.isEmpty) {
      LogService.instance.registerLog("[UploaderService] Queue is empty. Returning zero duration.");
      return Duration.zero; // PROBLEM HERE???????
    }

    // Filter already uploaded media
    final uploadedMedia = _uploadQueue.where((media) => media.isUploaded && media.uploadDuration != null);

    // If no uploaded media we can't calculate
    if (uploadedMedia.isEmpty) {
      LogService.instance.registerLog("[UploaderService] No uploaded media with valid durations. Returning zero duration.");
      return Duration.zero;
    }

    // Calculate total uploaded bytes
    final totalBytesUploaded = uploadedMedia.fold<num>(
      0,
          (sum, media) => sum + media.fileSizeInBytes,
    ).toInt();

    LogService.instance.registerLog("[UploaderService] Total bytes uploaded: $totalBytesUploaded");

    // Calculate total duration
    final totalDuration = uploadedMedia.fold<Duration>(
      Duration.zero,
          (sum, media) => sum + media.uploadDuration!,
    );

    LogService.instance.registerLog("[UploaderService] Total upload duration: ${totalDuration.inSeconds} seconds");

    // Avoid division by 0
    if (totalDuration.inSeconds == 0) {
      LogService.instance.registerLog("[UploaderService] Total upload duration is zero. Returning zero duration.");
      return Duration.zero;
    }

    // Average speed in bytes per second
    final averageSpeedBytesPerSecond = totalBytesUploaded / totalDuration.inSeconds;
    LogService.instance.registerLog("[UploaderService] Average speed: $averageSpeedBytesPerSecond bytes/second");

    // Calculate remaining bytes
    final remainingBytes = _uploadQueue.fold<num>(
      0,
          (sum, media) => sum + media.fileSizeInBytes,
    ).toInt();

    LogService.instance.registerLog("[UploaderService] Remaining bytes to upload: $remainingBytes");

    // Avoid division by 0 if no average speed
    if (averageSpeedBytesPerSecond <= 0) {
      LogService.instance.registerLog("[UploaderService] Average speed is zero or negative. Returning zero duration.");
      return Duration.zero;
    }

    // Calculate estimated time
    final estimatedSeconds = remainingBytes / averageSpeedBytesPerSecond;
    LogService.instance.registerLog("[UploaderService] Estimated time: $estimatedSeconds seconds");

    return Duration(seconds: estimatedSeconds.round());
  }


}
