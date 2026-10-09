import "package:flutter_test/flutter_test.dart";
import "package:hydracam/models/capture_session.dart";

void main() {
  test("retained capture belongs to its original human identity", () {
    final session = CaptureSession(
      sessionId: "owner-policy-unit-test",
      startTime: DateTime.utc(2026),
      humanOwnerIdentity: "issuer|subject-a",
    );
    expect(session.canUploadAs("issuer|subject-a"), true);
    expect(session.canUploadAs("issuer|subject-b"), false);
    expect(session.canUploadAs(null), false);
  });

  test("legacy or delegated capture cannot be claimed by signing in", () {
    final session = CaptureSession(
        sessionId: "legacy-policy-unit-test", startTime: DateTime.utc(2026));
    expect(session.canUploadAs("issuer|subject-a"), false);
    expect(session.canUploadAs(null), true);
  });
}
