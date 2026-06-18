import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/debug_session_policy.dart";

void main() {
  test("labels debug build session ids with debug prefix", () {
    final policy = DebugSessionPolicy(
      debugBuild: true,
      now: () => DateTime.utc(2026, 6, 18, 12, 34, 56),
      platformLabel: "android",
    );

    expect(
      policy.defaultSessionId(),
      "debug-android-20260618T123456Z",
    );
  });

  test("uses timestamp session ids outside debug builds", () {
    final policy = DebugSessionPolicy(
      debugBuild: false,
      now: () => DateTime.utc(2026, 6, 18, 12, 34, 56),
      platformLabel: "ios",
    );

    expect(
      policy.defaultSessionId(),
      DateTime.utc(2026, 6, 18, 12, 34, 56).toIso8601String(),
    );
  });

  test("debug sessions force local media deletion after upload", () {
    final policy = DebugSessionPolicy(
      debugBuild: true,
      now: () => DateTime.utc(2026, 6, 18),
      platformLabel: "android",
    );

    expect(policy.shouldDeleteUploadedLocalMedia(debugSession: true), isTrue);
    expect(policy.shouldDeleteUploadedLocalMedia(debugSession: false), isFalse);
  });
}
