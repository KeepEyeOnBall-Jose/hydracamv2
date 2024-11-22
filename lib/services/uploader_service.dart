import 'dart:async';
import 'dart:collection';
import 'dart:io';
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

  // Reference to the API service
  final HydraCamApiService _apiService = HydraCamApiService();

  void addMediaToQueue(dynamic media) {
    if (media is CapturedPhoto || media is CapturedVideo) {
      _uploadQueue.add(media);
      _startUploading();
    } else {
      LogService.instance.registerLog("Invalid media type added to upload queue");
    }
  }

  void _startUploading() {
    if (!_isUploading && _uploadQueue.isNotEmpty) {
      _processNextItem();
    }
  }

  void _processNextItem() async {
    if (_uploadQueue.isEmpty) {
      _isUploading = false;
      return;
    }

    _isUploading = true;
    final media = _uploadQueue.removeFirst();

    // Set upload start time
    media.uploadStartTime = DateTime.now();

    bool success = false;

    // Get session GUID
    String? sessionGuid = SessionManager.instance.sessionGuid;

    if (sessionGuid == null) {
      LogService.instance.registerLog("No session GUID available. Cannot upload media.");
      // Set media as not uploaded
      media.isUploaded = false;
      _isUploading = false;
      return;
    }

    // Prepare file
    File file = File(media.mediaPath);

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
      media.isUploaded = true;
      media.uploadDuration = DateTime.now().difference(media.uploadStartTime!);
      LogService.instance.registerLog("Media uploaded: ${media.mediaPath}");
    } else {
      media.isUploaded = false;
      LogService.instance.registerLog("Failed to upload media: ${media.mediaPath}");
    }

    // Notify listeners to update UI
    SessionManager.instance.notifyListeners();

    // Process next item
    _processNextItem();
  }

  bool get isUploading => _isUploading;

  int get queueLength => _uploadQueue.length;
}
