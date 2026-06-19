import "dart:async";
import "dart:collection";

import "../models/hls_stream_bundle.dart";
import "hls_stream_upload_service.dart";

typedef HlsBundleUploadHandler = Future<HlsStreamUploadResult> Function({
  required String sessionGuid,
  required HlsStreamBundle bundle,
  required String deviceId,
  required DateTime capturedAt,
  String? recordingId,
  HlsStreamTimingMetadata? timingMetadata,
});

typedef HlsUploadSleep = Future<void> Function(Duration duration);

enum HlsStreamUploadQueueStatus {
  pending,
  uploading,
  uploaded,
  failed,
}

class HlsStreamUploadQueueEntry {
  HlsStreamUploadQueueEntry({
    required this.sessionGuid,
    required this.bundle,
    required this.deviceId,
    required this.capturedAt,
    this.recordingId,
    this.timingMetadata,
  });

  final String sessionGuid;
  final HlsStreamBundle bundle;
  final String deviceId;
  final DateTime capturedAt;
  final String? recordingId;
  final HlsStreamTimingMetadata? timingMetadata;

  HlsStreamUploadQueueStatus status = HlsStreamUploadQueueStatus.pending;
  int attempts = 0;
  String? lastError;
  HlsStreamUploadResult? result;
}

class HlsStreamUploadQueue {
  HlsStreamUploadQueue({
    HlsStreamUploadService? uploadService,
    HlsBundleUploadHandler? uploadBundle,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
    HlsUploadSleep? sleep,
  })  : assert(maxAttempts > 0),
        _uploadBundle = uploadBundle ??
            (({
              required sessionGuid,
              required bundle,
              required deviceId,
              required capturedAt,
              recordingId,
              timingMetadata,
            }) {
              final service = uploadService ?? HlsStreamUploadService();
              return service.uploadBundle(
                sessionGuid: sessionGuid,
                bundle: bundle,
                deviceId: deviceId,
                capturedAt: capturedAt,
                recordingId: recordingId,
                timingMetadata: timingMetadata,
              );
            }),
        _sleep = sleep ?? Future<void>.delayed;

  final int maxAttempts;
  final Duration retryDelay;
  final HlsBundleUploadHandler _uploadBundle;
  final HlsUploadSleep _sleep;
  final Queue<HlsStreamUploadQueueEntry> _queue = Queue();

  bool _isUploading = false;
  Future<void>? _activeUploadDrain;

  bool get isUploading => _isUploading;
  int get queueLength => _queue.length;

  HlsStreamUploadQueueEntry addBundle({
    required String sessionGuid,
    required HlsStreamBundle bundle,
    required String deviceId,
    required DateTime capturedAt,
    String? recordingId,
    HlsStreamTimingMetadata? timingMetadata,
  }) {
    final entry = HlsStreamUploadQueueEntry(
      sessionGuid: sessionGuid,
      bundle: bundle,
      deviceId: deviceId,
      capturedAt: capturedAt,
      recordingId: recordingId,
      timingMetadata: timingMetadata,
    );
    _queue.add(entry);
    return entry;
  }

  Future<void> startUploadingManually() {
    if (_isUploading) {
      return _activeUploadDrain ?? Future<void>.value();
    }
    if (_queue.isEmpty) {
      return Future<void>.value();
    }
    final uploadDrain = _drainQueue();
    late final Future<void> trackedUploadDrain;
    trackedUploadDrain = uploadDrain.whenComplete(() {
      if (identical(_activeUploadDrain, trackedUploadDrain)) {
        _activeUploadDrain = null;
      }
    });
    _activeUploadDrain = trackedUploadDrain;
    return trackedUploadDrain;
  }

  Future<void> _drainQueue() async {
    _isUploading = true;
    try {
      while (_queue.isNotEmpty) {
        final entry = _queue.removeFirst();
        await _uploadWithRetry(entry);
      }
    } finally {
      _isUploading = false;
    }
  }

  Future<void> _uploadWithRetry(HlsStreamUploadQueueEntry entry) async {
    entry.status = HlsStreamUploadQueueStatus.uploading;
    while (entry.attempts < maxAttempts) {
      entry.attempts += 1;
      try {
        entry.result = await _uploadBundle(
          sessionGuid: entry.sessionGuid,
          bundle: entry.bundle,
          deviceId: entry.deviceId,
          capturedAt: entry.capturedAt,
          recordingId: entry.recordingId,
          timingMetadata: entry.timingMetadata,
        );
        entry.lastError = null;
        entry.status = HlsStreamUploadQueueStatus.uploaded;
        return;
      } catch (error) {
        entry.lastError = error.toString();
        if (entry.attempts >= maxAttempts) {
          entry.status = HlsStreamUploadQueueStatus.failed;
          return;
        }
        if (retryDelay > Duration.zero) {
          await _sleep(retryDelay);
        }
      }
    }
  }
}
