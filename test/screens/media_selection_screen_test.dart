import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";
import "package:hydracam/screens/media_selection_screen.dart";
import "package:photo_manager/photo_manager.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AssetEntity videoAsset({
    required String id,
    required DateTime createdAt,
    int durationSeconds = 60,
  }) {
    return AssetEntity(
      id: id,
      typeInt: AssetType.video.index,
      width: 200,
      height: 200,
      duration: durationSeconds,
      createDateSecond:
          createdAt.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
      title: "$id.mp4",
    );
  }

  testWidgets("video tiles show nearest candidate session display title",
      (tester) async {
    final candidateSession = CaptureSession(
      sessionId: "court-1",
      sessionGuid: "guid-court-1",
      displayName: "Squash match - Court 1",
      startTime: DateTime.utc(2026, 6, 8, 10),
      endTime: DateTime.utc(2026, 6, 8, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaSelectionScreen(
          mediaList: [
            videoAsset(
              id: "near-session",
              createdAt: DateTime.utc(2026, 6, 8, 10, 34),
            ),
            videoAsset(
              id: "outside-session",
              createdAt: DateTime.utc(2026, 6, 8, 12),
            ),
          ],
          candidateSessions: [candidateSession],
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text("Candidate: Squash match - Court 1 - 4 min after session"),
      findsOneWidget,
    );
    expect(find.text("Candidate: guid-court-1 - 4 min after session"),
        findsNothing);
    expect(find.text("Candidate: court-1"), findsNothing);
    expect(find.text("Candidate: outside-session"), findsNothing);
  });

  testWidgets("video candidate label falls back to session id without guid",
      (tester) async {
    final candidateSession = CaptureSession(
      sessionId: "legacy-session-id",
      startTime: DateTime.utc(2026, 6, 8, 10),
      endTime: DateTime.utc(2026, 6, 8, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaSelectionScreen(
          mediaList: [
            videoAsset(
              id: "near-legacy-session",
              createdAt: DateTime.utc(2026, 6, 8, 10, 34),
            ),
          ],
          candidateSessions: [candidateSession],
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text("Candidate: legacy-session-id - 4 min after session"),
      findsOneWidget,
    );
  });
}
