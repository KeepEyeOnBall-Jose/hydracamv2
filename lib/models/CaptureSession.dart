import 'CapturedPhoto.dart';

/// Represents a session of photo or video capture, storing all captured photos
/// and related metadata for the session.
class CaptureSession {
  /// A unique identifier for the capture session, typically generated as a timestamp.
  final String sessionId;

  /// The date and time when the capture session started.
  final DateTime startTime;

  /// The date and time when the capture session ended (nullable, set when the session ends).
  DateTime? endTime;

  /// A list of photos captured during this session.
  final List<CapturedPhoto> capturedPhotos;

  /// Constructor to initialize a CaptureSession with a unique ID, start time,
  /// and an optional list of captured photos.
  ///
  /// If no list of photos is provided, an empty list is used.
  CaptureSession({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    List<CapturedPhoto>? capturedPhotos,
  }) : capturedPhotos = capturedPhotos ?? [];

  /// Adds a captured photo to the session.
  void addPhoto(CapturedPhoto photo) {
    capturedPhotos.add(photo);
  }

  /// Marks the session as ended by setting the `endTime` to the current date and time.
  void endSession() {
    endTime = DateTime.now();
  }
}