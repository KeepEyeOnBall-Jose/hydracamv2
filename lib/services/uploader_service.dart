import 'dart:async';
import 'dart:collection';
import '../models/CapturedPhoto.dart';
import '../models/CapturedVideo.dart';
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

    // Simulate upload delay
    await Future.delayed(const Duration(seconds: 2)); // Simulated upload duration

    // Update media upload status
    media.isUploaded = true;
    media.uploadDuration = DateTime.now().difference(media.uploadStartTime!);

    LogService.instance.registerLog("Media uploaded: ${media.mediaPath}");

    // Notify listeners to update UI
    SessionManager.instance.notifyListeners();

    // Process next item
    _processNextItem();
  }

  bool get isUploading => _isUploading;

  int get queueLength => _uploadQueue.length;
}
