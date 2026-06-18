import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";

void main() {
  test("preferred identifier uses session guid when available", () {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "backend-session-guid",
      startTime: DateTime.utc(2026, 6, 9),
    );

    expect(session.preferredIdentifier, "backend-session-guid");
  });

  test("preferred identifier falls back to session id without guid", () {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      startTime: DateTime.utc(2026, 6, 9),
    );

    expect(session.preferredIdentifier, "legacy-session-id");
  });

  test("preferred identifier falls back to session id for blank guid", () {
    final session = CaptureSession(
      sessionId: "legacy-session-id",
      sessionGuid: "  ",
      startTime: DateTime.utc(2026, 6, 18),
    );

    expect(session.preferredIdentifier, "legacy-session-id");
  });
}
