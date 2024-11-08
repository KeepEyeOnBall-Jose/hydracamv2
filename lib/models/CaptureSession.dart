import 'CapturedPhoto.dart';
import 'CapturedVideo.dart';

/// Represents a session of photo or video capture, storing all captured photos,
/// videos, and related metadata for the session.
class CaptureSession {
  /// A unique identifier for the capture session, typically generated as a timestamp.
  final String sessionId;

  /// A guid returned by API.
  String? sessionGuid;

  /// The date and time when the capture session started.
  final DateTime startTime;

  /// The date and time when the capture session ended (nullable, set when the session ends).
  DateTime? endTime;

  /// A list of photos captured during this session.
  final List<CapturedPhoto> capturedPhotos;

  /// A list of videos captured during this session.
  final List<CapturedVideo> capturedVideos;

  /// Constructor to initialize a CaptureSession with a unique ID, start time,
  /// and optional lists of captured photos and videos.
  ///
  /// If no lists are provided, empty lists are used.
  CaptureSession({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    List<CapturedPhoto>? capturedPhotos,
    List<CapturedVideo>? capturedVideos,
  })  : capturedPhotos = capturedPhotos ?? [],
        capturedVideos = capturedVideos ?? [];

  /// Adds a captured photo to the session.
  void addPhoto(CapturedPhoto photo) {
    capturedPhotos.add(photo);
  }

  /// Adds a captured video to the session.
  void addVideo(CapturedVideo video) {
    capturedVideos.add(video);
  }

  /// Marks the session as ended by setting the `endTime` to the current date and time.
  void endSession() {
    endTime = DateTime.now();
  }
}
