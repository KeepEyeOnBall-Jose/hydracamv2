import "dart:async";
import "dart:collection";
import "dart:io";
import "package:flutter/cupertino.dart";
import "settings_service.dart";
import "../models/captured_photo.dart";
import "../models/captured_video.dart";
import "hydracam_api_service.dart";
import "session_manager.dart";
import "log_service.dart";

/// Singleton Module that manages the upload process of every media file recorded
class UploaderService {
  // Singleton pattern
  static final UploaderService _instance = UploaderService._internal();
  factory UploaderService() => _instance;
  UploaderService._internal();

  final Queue<dynamic> _uploadQueue = Queue();
  final Queue<dynamic> _completedUploadSamples = Queue();
  bool _isUploading = false;
  int _uploadGeneration = 0;
  int? _resumeQueueAfterCancelledUploadGeneration;
  DateTime Function() _now = DateTime.now;
  Future<void>? _activeUploadDrain;

  final ValueNotifier<Duration> estimatedTimeNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<dynamic> currentlyUploadingNotifier = ValueNotifier(null);

  // Reference to the API service
  final HydraCamApiService _apiService = HydraCamApiService();

  static const String _serviceSessionRequiredMessage =
      "Upload blocked: no active service session is available for this media.";
  static const String _missingUploadFileMessage =
      "Upload failed: file does not exist on disk.";
  static const String _cancelledUploadMessage = "Upload cancelled.";

  // To track and notify process upload
  ValueNotifier<double> uploadProgressNotifier = ValueNotifier(0.0);

  static void configureNowForTests(DateTime Function() now) {
    _instance._now = now;
  }

  static void resetNowForTests() {
    _instance._now = DateTime.now;
  }

  /// Processes a media file (photo or video) and adds it to the queue
  Future<void> addMediaToQueue(dynamic media) async {
    if (media is CapturedPhoto || media is CapturedVideo) {
      if (media.isUploaded) {
        LogService.instance
            .registerLog("Media already uploaded: ${media.mediaPath}");
        return;
      }

      if (!SessionManager.instance.canUploadCurrentSession) {
        _markUploadBlocked(media, _serviceSessionRequiredMessage);
        LogService.instance.registerLog(_serviceSessionRequiredMessage);
        await SessionManager.instance.updateMetadata();
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        SessionManager.instance.notifyListeners();
        return;
      }

      final currentUpload = currentlyUploadingNotifier.value;
      if (currentUpload != null && currentUpload.mediaPath == media.mediaPath) {
        LogService.instance
            .registerLog("Media already uploading: ${media.mediaPath}");
        return;
      }

      // Avoid duplicates
      if (_uploadQueue.any((item) => item.mediaPath == media.mediaPath)) {
        LogService.instance
            .registerLog("Media already in queue: ${media.mediaPath}");
        return; // Don't add if already in the queue
      }

      // Add media to queue
      media.uploadFailureReason = null;
      _uploadQueue.add(media);
      estimatedTimeNotifier.value = estimateTotalTimeRemaining();
      LogService.instance
          .registerLog("Media added to upload queue: ${media.mediaPath}");

      // Check if auto-upload setting is active
      final autoUploadEnabled =
          await SettingsService.getAutoUploadMaterials(); // Check the setting

      if (autoUploadEnabled) {
        LogService.instance
            .registerLog("Auto-upload is enabled. Starting upload process.");
        unawaited(_startUploading());
      } else {
        LogService.instance.registerLog(
            "Auto-upload is disabled. Media added to queue but not uploaded.");
      }
    } else {
      LogService.instance
          .registerLog("Invalid media type added to upload queue");
    }
  }

  /// Iterates whole queue until all media is uploaded
  Future<void> _startUploading() {
    LogService.instance.registerLog(
        "UploaderService: _startUploading called. _isUploading=$_isUploading, queue length=${_uploadQueue.length}");
    if (_isUploading) {
      return _activeUploadDrain ?? Future<void>.value();
    }
    if (_uploadQueue.isEmpty) {
      return Future<void>.value();
    }
    final uploadDrain = _processNextItem();
    late final Future<void> trackedUploadDrain;
    trackedUploadDrain = uploadDrain.whenComplete(() {
      if (identical(_activeUploadDrain, trackedUploadDrain)) {
        _activeUploadDrain = null;
      }
    });
    _activeUploadDrain = trackedUploadDrain;
    return trackedUploadDrain;
  }

  /// Forces _startUploading manually
  Future<void> startUploadingManually() async {
    if (_isUploading) {
      await _startUploading();
    } else if (_uploadQueue.isEmpty) {
      LogService.instance.registerLog("No items in queue to upload.");
    } else {
      LogService.instance.registerLog("Manual upload initiated.");
      await _startUploading();
    }
  }

  Future<bool> cancelQueuedMedia(dynamic media) async {
    final mediaPath = media.mediaPath;
    dynamic pendingItem;
    for (final item in _uploadQueue) {
      if (item.mediaPath == mediaPath) {
        pendingItem = item;
        break;
      }
    }
    if (pendingItem == null) {
      LogService.instance
          .registerLog("No pending queued media to cancel: $mediaPath");
      return false;
    }

    _uploadQueue.remove(pendingItem);
    _markUploadBlocked(pendingItem, _cancelledUploadMessage);
    await _persistUploadStateNow();
    estimatedTimeNotifier.value = estimateTotalTimeRemaining();
    LogService.instance.registerLog("Cancelled pending upload: $mediaPath");
    return true;
  }

  Future<bool> cancelMediaUpload(dynamic media) {
    final currentUpload = currentlyUploadingNotifier.value;
    if (currentUpload != null && currentUpload.mediaPath == media.mediaPath) {
      return cancelCurrentUpload();
    }
    return cancelQueuedMedia(media);
  }

  Future<bool> cancelCurrentUpload() async {
    final currentUpload = currentlyUploadingNotifier.value;
    if (currentUpload == null) {
      LogService.instance.registerLog("No active upload to cancel.");
      return false;
    }

    final wasUploading = _isUploading;
    final cancelledUploadGeneration = _uploadGeneration;
    if (wasUploading) {
      _apiService.cancelInFlightRequests();
    }
    _uploadGeneration += 1;
    _resumeQueueAfterCancelledUploadGeneration =
        _uploadQueue.isEmpty ? null : cancelledUploadGeneration;
    _isUploading = false;
    currentlyUploadingNotifier.value = null;
    uploadProgressNotifier.value = 0.0;
    estimatedTimeNotifier.value = estimateTotalTimeRemaining();
    currentUpload.isUploaded = false;
    currentUpload.uploadFailureReason = _cancelledUploadMessage;
    if (wasUploading) {
      await _persistUploadStateNow();
    }

    LogService.instance
        .registerLog("Cancelled active upload: ${currentUpload.mediaPath}");
    return true;
  }

  /// Processes next item of the queue. Uploads it, notifies possible error, and triggers local file deletion.
  Future<void> _processNextItem() async {
    LogService.instance.registerLog(
        "UploaderService: _processNextItem called. Queue length=${_uploadQueue.length}");

    // Check if there is anything in the queue
    if (_uploadQueue.isEmpty) {
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      estimatedTimeNotifier.value = Duration.zero;
      uploadProgressNotifier.value = 0.0;
      LogService.instance
          .registerLog("UploaderService: Queue is empty. Uploading stopped.");
      return;
    }

    _isUploading = true;
    final media = _uploadQueue.removeFirst();
    currentlyUploadingNotifier.value = media;
    final uploadGeneration = _uploadGeneration;

    // Set upload start time
    media.uploadStartTime = _now();

    bool success = false;

    // Get session GUID
    final String? sessionGuid = SessionManager.instance.sessionGuid;
    LogService.instance
        .registerLog("UploaderService: sessionGuid=$sessionGuid");

    if (sessionGuid == null) {
      LogService.instance
          .registerLog("No session GUID available. Cannot upload media.");
      // Set media as not uploaded
      _markUploadBlocked(
          media, "Upload blocked: no active backend session GUID.");
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      return;
    }

    if (!SessionManager.instance.canUploadCurrentSession) {
      _markUploadBlocked(media, _serviceSessionRequiredMessage);
      LogService.instance.registerLog(_serviceSessionRequiredMessage);
      await SessionManager.instance.updateMetadata();
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      estimatedTimeNotifier.value = estimateTotalTimeRemaining();
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      SessionManager.instance.notifyListeners();
      await _processNextItem();
      return;
    }

    // Prepare file
    final File file = File(media.mediaPath);

    // Check if file exists
    if (!file.existsSync()) {
      LogService.instance
          .registerLog("UploaderService: File does not exist: ${file.path}");
      _markUploadBlocked(media, _missingUploadFileMessage);
      await SessionManager.instance.updateMetadata();
      _isUploading = false;
      currentlyUploadingNotifier.value = null;
      estimatedTimeNotifier.value = estimateTotalTimeRemaining();
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      SessionManager.instance.notifyListeners();
      await _processNextItem();
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
        (progress) {
          uploadProgressNotifier.value = progress; // Notify progress
        },
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
        (progress) {
          uploadProgressNotifier.value = progress; // Notify progress
        },
        recordingEndDate: media.endRecordingDate,
        recordingDuration:
            media.endRecordingDate.difference(media.startRecordingDate),
      );
    }

    if (uploadGeneration != _uploadGeneration) {
      LogService.instance.registerLog(
          "Ignoring stale upload completion after uploader reset or cancellation: ${media.mediaPath}");
      if (_resumeQueueAfterCancelledUploadGeneration == uploadGeneration) {
        _resumeQueueAfterCancelledUploadGeneration = null;
        if (!_isUploading && _uploadQueue.isNotEmpty) {
          await _processNextItem();
        }
      }
      return;
    }

    if (success) {
      // Update metadata and register log
      media.isUploaded = true;
      media.uploadFailureReason = null;
      media.uploadDuration = _now().difference(media.uploadStartTime!);
      _recordCompletedUploadSample(media);
      LogService.instance.registerLog("Media uploaded: ${media.mediaPath}");

      // Update metadata.json with uploaded media
      await SessionManager.instance.updateMetadata();

      // Trigger deletion of the local file
      await SessionManager.instance.deleteFileIfAllowed(media.mediaPath);
    } else {
      media.isUploaded = false;
      media.uploadFailureReason =
          "Upload failed; check logs for webservice response.";
      LogService.instance
          .registerLog("Failed to upload media: ${media.mediaPath}");
      await SessionManager.instance.updateMetadata();
    }

    // Notify listeners to update UI
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    SessionManager.instance.notifyListeners();
    currentlyUploadingNotifier.value = null;

    // Recalculate estimated time
    estimatedTimeNotifier.value = estimateTotalTimeRemaining();

    // Process next item
    await _processNextItem();
  }

  bool get isUploading => _isUploading;

  int get queueLength => _uploadQueue.length;

  void _markUploadBlocked(dynamic media, String reason) {
    media.isUploaded = false;
    media.uploadStartTime ??= _now();
    media.uploadFailureReason = reason;
  }

  Future<void> _persistUploadStateNow() async {
    await SessionManager.instance.updateMetadata();
  }

  void _recordCompletedUploadSample(dynamic media) {
    _completedUploadSamples.add(media);
    while (_completedUploadSamples.length > 10) {
      _completedUploadSamples.removeFirst();
    }
  }

  /// Estimates the time remaining to upload all files in the queue based on past uploads.
  Duration estimateTotalTimeRemaining() {
    // If queue empty there is no estimated time
    if (_uploadQueue.isEmpty) {
      LogService.instance.registerLog(
          "[UploaderService] Queue is empty. Returning zero duration.");
      return Duration.zero; // PROBLEM HERE???????
    }

    // Filter already uploaded media
    final uploadedMedia = _completedUploadSamples
        .where((media) => media.isUploaded && media.uploadDuration != null);

    // If no uploaded media we can't calculate
    if (uploadedMedia.isEmpty) {
      LogService.instance.registerLog(
          "[UploaderService] No uploaded media with valid durations. Returning zero duration.");
      return Duration.zero;
    }

    // Calculate total uploaded bytes
    final totalBytesUploaded = uploadedMedia
        .fold<num>(
          0,
          (sum, media) => sum + media.fileSizeInBytes,
        )
        .toInt();

    LogService.instance.registerLog(
        "[UploaderService] Total bytes uploaded: $totalBytesUploaded");

    // Calculate total duration
    final totalDuration = uploadedMedia.fold<Duration>(
      Duration.zero,
      (sum, media) => sum + media.uploadDuration!,
    );

    LogService.instance.registerLog(
        "[UploaderService] Total upload duration: ${totalDuration.inSeconds} seconds");

    // Avoid division by 0
    final totalDurationSeconds =
        totalDuration.inMicroseconds / Duration.microsecondsPerSecond;
    if (totalDurationSeconds <= 0) {
      LogService.instance.registerLog(
          "[UploaderService] Total upload duration is zero. Returning zero duration.");
      return Duration.zero;
    }

    // Average speed in bytes per second
    final averageSpeedBytesPerSecond =
        totalBytesUploaded / totalDurationSeconds;
    LogService.instance.registerLog(
        "[UploaderService] Average speed: $averageSpeedBytesPerSecond bytes/second");

    // Calculate remaining bytes
    final remainingBytes = _uploadQueue
        .fold<num>(
          0,
          (sum, media) => sum + media.fileSizeInBytes,
        )
        .toInt();

    LogService.instance.registerLog(
        "[UploaderService] Remaining bytes to upload: $remainingBytes");

    // Avoid division by 0 if no average speed
    if (averageSpeedBytesPerSecond <= 0) {
      LogService.instance.registerLog(
          "[UploaderService] Average speed is zero or negative. Returning zero duration.");
      return Duration.zero;
    }

    // Calculate estimated time
    final estimatedSeconds = remainingBytes / averageSpeedBytesPerSecond;
    LogService.instance.registerLog(
        "[UploaderService] Estimated time: $estimatedSeconds seconds");

    return Duration(
      milliseconds: (estimatedSeconds * Duration.millisecondsPerSecond).round(),
    );
  }

  /// Resets the UploaderService by clearing the queue and resetting the internal state.
  void reset() {
    LogService.instance
        .registerLog("UploaderService: Resetting upload queue and state.");
    final hadActiveUpload =
        _isUploading || currentlyUploadingNotifier.value != null;
    _uploadGeneration += 1;
    _resumeQueueAfterCancelledUploadGeneration = null;
    if (hadActiveUpload) {
      _apiService.cancelInFlightRequests();
    }

    // Clear the upload queue to remove any pending media from the previous session
    _uploadQueue.clear();
    _completedUploadSamples.clear();

    // Reset the uploading flag to ensure no ongoing uploads remain
    _isUploading = false;

    // Clear current upload notifier and reset estimated time notifier
    currentlyUploadingNotifier.value = null;
    estimatedTimeNotifier.value = Duration.zero;
    uploadProgressNotifier.value = 0.0;

    LogService.instance.registerLog("UploaderService: Reset completed.");
  }
}
