import "dart:io";
import "dart:typed_data";

/// CapturedVideo - Represents a video captured by a slave device.
/// This class holds the binary data of the video (temporarily), the file path where it's stored,
/// the device ID that recorded the video, and the timestamps for when it was started, ended, and received.
class CapturedVideo {
  /// The binary data of the captured video. This is nullable and can be
  /// set to `null` once the video is saved to disk to free up memory.
  Uint8List? videoData;

  /// The file path where the video is stored on the master device.
  final String videoPath;

  /// The unique identifier for the slave device that recorded the video.
  final String slaveDeviceId;

  /// The date and time when the video recording started.
  final DateTime startRecordingDate;

  /// The date and time when the video recording ended.
  final DateTime endRecordingDate;

  /// The date and time when the video was received by the master device.
  final DateTime receivedDate;

  /// Flag to track upload status
  bool isUploaded;

  /// Metadata about upload elapsed time
  Duration? uploadDuration; // to track upload time
  DateTime? uploadStartTime; // to track upload start time

  /// File size metadata
  final int fileSizeInBytes;

  /// Constructor for creating a new CapturedVideo.
  ///
  /// - `videoData`: The binary data of the video (can be null once saved).
  /// - `videoPath`: The file path where the video is stored.
  /// - `slaveDeviceId`: The ID of the slave device that recorded the video.
  /// - `startRecordingDate`: The timestamp when the video recording started.
  /// - `endRecordingDate`: The timestamp when the video recording ended.
  /// - `receivedDate`: The timestamp when the video was received by the master.
  CapturedVideo({
    this.videoData, // Now nullable
    required this.videoPath,
    required this.slaveDeviceId,
    required this.startRecordingDate,
    required this.endRecordingDate,
    required this.receivedDate,
    this.isUploaded = false,
    this.uploadDuration,
    this.uploadStartTime,
  }) : fileSizeInBytes = File(videoPath).lengthSync().toInt();

  /// Getter for media path (used by UploaderService)
  String get mediaPath => videoPath;
}
