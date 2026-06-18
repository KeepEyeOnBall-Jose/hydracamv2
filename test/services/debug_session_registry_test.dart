import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/debug_session_registry.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test("records and removes debug service sessions", () async {
    final registry = DebugSessionRegistry();

    await registry.record(
      const DebugSessionRef(
        sessionGuid: "debug-guid",
        sessionId: "debug-android-20260618T123456Z",
        serviceNumericId: 456,
      ),
    );

    expect(await registry.list(), [
      const DebugSessionRef(
        sessionGuid: "debug-guid",
        sessionId: "debug-android-20260618T123456Z",
        serviceNumericId: 456,
      ),
    ]);

    await registry.remove("debug-guid");

    expect(await registry.list(), isEmpty);
  });
}
