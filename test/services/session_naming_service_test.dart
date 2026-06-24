import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_naming_service.dart";

void main() {
  test("builds a default name from activity, location, players, and time", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Squash match",
        sportsCenterName: "Sportwerk",
        courtName: "Court 2",
        players: const ["Ana", "Luis"],
        startTime: DateTime(2026, 6, 22, 19, 30),
      ),
    );

    expect(
      name,
      "Squash match - Sportwerk Court 2 - Ana vs Luis - 2026-06-22 19:30",
    );
  });

  test("omits missing players without leaving doubled separators", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Training",
        sportsCenterName: null,
        courtName: "Court 3",
        players: const [],
        startTime: DateTime(2026, 6, 22, 8, 5),
      ),
    );

    expect(name, "Training - Court 3 - 2026-06-22 08:05");
  });

  test("falls back to a plain session name when no context is available", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "",
        sportsCenterName: null,
        courtName: null,
        players: const [],
        startTime: DateTime(2026, 6, 22, 8, 5),
      ),
    );

    expect(name, "Session - 2026-06-22 08:05");
  });

  test("sanitizes custom names for compact UI and metadata storage", () {
    expect(
      sessionNamingService.sanitizeCustomName(
        "  Finals\nCourt   1   with   extra spacing  ",
      ),
      "Finals Court 1 with extra spacing",
    );
  });
}
