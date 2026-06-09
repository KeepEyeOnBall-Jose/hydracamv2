import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";
import "package:hydracam/models/captured_video.dart";
import "package:hydracam/services/gallery_session_matcher.dart";

void main() {
  const matcher = GallerySessionMatcher();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync("gallery_session_matcher");
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  CapturedVideo video({
    required String name,
    required DateTime start,
    required DateTime end,
  }) {
    final file = File("${tempDir.path}/$name.mp4")
      ..writeAsBytesSync([1, 2, 3, 4]);
    return CapturedVideo(
      videoPath: file.path,
      slaveDeviceId: "gallery-device",
      startRecordingDate: start,
      endRecordingDate: end,
      receivedDate: end.add(const Duration(seconds: 1)),
    );
  }

  CaptureSession session({
    required String id,
    required DateTime start,
    required DateTime end,
  }) {
    return CaptureSession(
      sessionId: id,
      sessionGuid: "guid-$id",
      startTime: start,
      endTime: end,
    );
  }

  test("matches gallery videos inside an explicit session margin", () {
    final playedSession = session(
      id: "court-1",
      start: DateTime.utc(2026, 6, 8, 10),
      end: DateTime.utc(2026, 6, 8, 10, 30),
    );
    final laterSession = session(
      id: "court-2",
      start: DateTime.utc(2026, 6, 8, 11),
      end: DateTime.utc(2026, 6, 8, 11, 30),
    );
    final importedVideo = video(
      name: "near-session",
      start: DateTime.utc(2026, 6, 8, 10, 43),
      end: DateTime.utc(2026, 6, 8, 10, 44),
    );

    final candidates = matcher.findVideoCandidates(
      video: importedVideo,
      sessions: [playedSession, laterSession],
      margin: const Duration(minutes: 15),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.session.sessionId, "court-1");
    expect(
      candidates.single.matchingWindowStart,
      DateTime.utc(2026, 6, 8, 9, 45),
    );
    expect(
      candidates.single.matchingWindowEnd,
      DateTime.utc(2026, 6, 8, 10, 45),
    );
    expect(candidates.single.timeGap, const Duration(minutes: 13));
    expect(candidates.single.overlapsSession, isFalse);
  });

  test("excludes videos outside the margin and ranks nearest candidates first",
      () {
    final earlySession = session(
      id: "early",
      start: DateTime.utc(2026, 6, 8, 10),
      end: DateTime.utc(2026, 6, 8, 10, 30),
    );
    final laterSession = session(
      id: "later",
      start: DateTime.utc(2026, 6, 8, 10, 50),
      end: DateTime.utc(2026, 6, 8, 11),
    );
    final betweenSessions = video(
      name: "between-sessions",
      start: DateTime.utc(2026, 6, 8, 10, 43),
      end: DateTime.utc(2026, 6, 8, 10, 44),
    );
    final outsideWindow = video(
      name: "outside-window",
      start: DateTime.utc(2026, 6, 8, 11, 25),
      end: DateTime.utc(2026, 6, 8, 11, 26),
    );

    final rankedCandidates = matcher.findVideoCandidates(
      video: betweenSessions,
      sessions: [earlySession, laterSession],
      margin: const Duration(minutes: 20),
    );

    expect(
      rankedCandidates.map((candidate) => candidate.session.sessionId),
      ["later", "early"],
    );
    expect(rankedCandidates.first.timeGap, const Duration(minutes: 6));
    expect(rankedCandidates.last.timeGap, const Duration(minutes: 13));

    expect(
      matcher.findVideoCandidates(
        video: outsideWindow,
        sessions: [earlySession, laterSession],
        margin: const Duration(minutes: 20),
      ),
      isEmpty,
    );
  });

  test("matches raw video time ranges without requiring a saved video file",
      () {
    final playedSession = session(
      id: "court-range",
      start: DateTime.utc(2026, 6, 8, 12),
      end: DateTime.utc(2026, 6, 8, 12, 30),
    );

    final candidates = matcher.findVideoRangeCandidates(
      videoStart: DateTime.utc(2026, 6, 8, 12, 34),
      videoEnd: DateTime.utc(2026, 6, 8, 12, 36),
      sessions: [playedSession],
      margin: const Duration(minutes: 10),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.session.sessionId, "court-range");
    expect(candidates.single.timeGap, const Duration(minutes: 4));
  });
}
