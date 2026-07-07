import "captured_photo.dart";
import "captured_video.dart";

/// Represents a session of photo or video capture, storing all captured photos,
/// videos, and related metadata for the session.
class CaptureSession {
  /// A unique identifier for the capture session, typically generated as a timestamp.
  final String sessionId;

  /// A guid returned by API.
  String? sessionGuid;

  /// Human-readable operator-facing name. This is not an API identifier.
  String? displayName;

  /// The date and time when the capture session started.
  final DateTime startTime;

  /// The date and time when the capture session ended (nullable, set when the session ends).
  DateTime? endTime;

  /// A list of photos captured during this session.
  final List<CapturedPhoto> capturedPhotos;

  /// A list of videos captured during this session.
  final List<CapturedVideo> capturedVideos;

  /// Whether this service-created session is a debug build artifact.
  final bool debugSession;

  /// Numeric service id returned by the current MoBo API when available.
  final int? serviceNumericId;

  /// media-timeline event id returned by the bridge when available.
  String? mediaTimelineEventId;

  /// Bearer token returned by the media-timeline bridge for direct uploads.
  /// Runtime-only: do not write this secret into durable metadata files.
  String? mediaTimelineUploadToken;

  /// Unix epoch milliseconds when [mediaTimelineUploadToken] expires.
  int? mediaTimelineUploadTokenExpiresAt;

  /// Constructor to initialize a CaptureSession with a unique ID, start time,
  /// and optional lists of captured photos and videos.
  ///
  /// If no lists are provided, empty lists are used.
  CaptureSession({
    required this.sessionId,
    this.sessionGuid,
    this.displayName,
    required this.startTime,
    this.endTime,
    List<CapturedPhoto>? capturedPhotos,
    List<CapturedVideo>? capturedVideos,
    this.debugSession = false,
    this.serviceNumericId,
    this.mediaTimelineEventId,
    this.mediaTimelineUploadToken,
    this.mediaTimelineUploadTokenExpiresAt,
  })  : capturedPhotos = capturedPhotos ?? [],
        capturedVideos = capturedVideos ?? [];

  /// Prefer the backend/API GUID for cross-device references, falling back to
  /// the legacy session ID for older local metadata.
  String get preferredIdentifier {
    final guid = sessionGuid?.trim();
    if (guid != null && guid.isNotEmpty) {
      return guid;
    }
    return sessionId;
  }

  /// Prefer the operator-facing display name for UI, falling back to the stable
  /// identifier used by storage and backend calls.
  String get displayTitle {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return preferredIdentifier;
  }

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
