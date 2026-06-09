import "../models/capture_session.dart";
import "../models/captured_video.dart";

class GallerySessionCandidate {
  final CaptureSession session;
  final DateTime matchingWindowStart;
  final DateTime matchingWindowEnd;
  final Duration timeGap;

  const GallerySessionCandidate({
    required this.session,
    required this.matchingWindowStart,
    required this.matchingWindowEnd,
    required this.timeGap,
  });

  bool get overlapsSession => timeGap == Duration.zero;
}

class GallerySessionMatcher {
  const GallerySessionMatcher();

  static const Duration defaultMargin = Duration(minutes: 15);

  List<GallerySessionCandidate> findVideoCandidates({
    required CapturedVideo video,
    required Iterable<CaptureSession> sessions,
    Duration margin = defaultMargin,
  }) {
    return findVideoRangeCandidates(
      videoStart: video.startRecordingDate,
      videoEnd: video.endRecordingDate,
      sessions: sessions,
      margin: margin,
    );
  }

  List<GallerySessionCandidate> findVideoRangeCandidates({
    required DateTime videoStart,
    required DateTime videoEnd,
    required Iterable<CaptureSession> sessions,
    Duration margin = defaultMargin,
  }) {
    if (margin.isNegative) {
      throw ArgumentError.value(margin, "margin", "must not be negative");
    }

    final candidates = <GallerySessionCandidate>[];
    for (final session in sessions) {
      final sessionEnd = session.endTime ?? session.startTime;
      final matchingWindowStart = session.startTime.subtract(margin);
      final matchingWindowEnd = sessionEnd.add(margin);

      if (!_rangesOverlap(
        videoStart,
        videoEnd,
        matchingWindowStart,
        matchingWindowEnd,
      )) {
        continue;
      }

      candidates.add(
        GallerySessionCandidate(
          session: session,
          matchingWindowStart: matchingWindowStart,
          matchingWindowEnd: matchingWindowEnd,
          timeGap: _timeGap(
            videoStart,
            videoEnd,
            session.startTime,
            sessionEnd,
          ),
        ),
      );
    }

    candidates.sort((left, right) {
      final gapComparison = left.timeGap.compareTo(right.timeGap);
      if (gapComparison != 0) {
        return gapComparison;
      }
      return right.session.startTime.compareTo(left.session.startTime);
    });
    return candidates;
  }

  static bool _rangesOverlap(
    DateTime leftStart,
    DateTime leftEnd,
    DateTime rightStart,
    DateTime rightEnd,
  ) {
    return !leftEnd.isBefore(rightStart) && !leftStart.isAfter(rightEnd);
  }

  static Duration _timeGap(
    DateTime videoStart,
    DateTime videoEnd,
    DateTime sessionStart,
    DateTime sessionEnd,
  ) {
    if (_rangesOverlap(videoStart, videoEnd, sessionStart, sessionEnd)) {
      return Duration.zero;
    }
    if (videoEnd.isBefore(sessionStart)) {
      return sessionStart.difference(videoEnd);
    }
    return videoStart.difference(sessionEnd);
  }
}
