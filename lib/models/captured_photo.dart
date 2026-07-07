import "dart:typed_data";

import "capture_context_metadata.dart";
import "media_file_utils.dart";
import "sync_metadata.dart";

/// CapturedPhoto - Represents a photo captured by a slave device.
/// This class holds the binary data of the photo (temporarily), the file path where it's stored,
/// the device ID that took the photo, and the timestamps for when it was captured
/// and when it was received by the master.
class CapturedPhoto {
  /// The binary data of the captured photo. This is nullable and can be
  /// set to `null` once the photo is saved to disk to free up memory.
  Uint8List? photoData;

  /// The file path where the photo is stored on the master device.
  final String photoPath;

  /// The unique identifier for the slave device that took the photo.
  final String slaveDeviceId;

  /// The date and time when the photo was captured.
  final DateTime captureDate;

  /// The date and time when the photo was received by the master device.
  final DateTime receivedDate;

  /// Setup metadata captured from the local device before the media was saved.
  final MediaCaptureContext? captureContext;

  /// Clock-synchronization quality at the moment of capture, used to align this
  /// photo against other devices' media. Null when no calibration is available.
  final SyncMetadata? syncMetadata;

  /// Flag to track upload status
  bool isUploaded;

  /// Metadata about upload elapsed time
  Duration? uploadDuration; // to track upload time
  DateTime? uploadStartTime; // to track upload start time
  String? uploadFailureReason;

  /// File size metadata
  final int fileSizeInBytes;

  /// media-timeline/File Registry identity returned after bridge upload.
  String? mediaTimelineEventId;
  String? fileRegistryFileId;

  /// Constructor for creating a new CapturedPhoto.
  ///
  /// - `photoData`: The binary data of the photo (can be null once saved).
  /// - `photoPath`: The file path where the photo is stored.
  /// - `slaveDeviceId`: The ID of the slave device that captured the photo.
  /// - `captureDate`: The timestamp when the photo was captured.
  /// - `receivedDate`: The timestamp when the photo was received by the master.
  CapturedPhoto({
    this.photoData, // Now nullable
    required this.photoPath,
    required this.slaveDeviceId,
    required this.captureDate,
    required this.receivedDate,
    this.captureContext,
    this.syncMetadata,
    this.isUploaded = false,
    this.uploadDuration,
    this.uploadStartTime,
    this.uploadFailureReason,
    this.mediaTimelineEventId,
    this.fileRegistryFileId,
    int? fileSizeInBytes,
  }) : fileSizeInBytes = fileSizeInBytes ?? safeFileSizeOf(photoPath);

  /// Getter for media path (used by UploaderService)
  String get mediaPath => photoPath;
}
