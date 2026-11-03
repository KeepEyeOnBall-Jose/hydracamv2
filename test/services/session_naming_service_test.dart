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

  test("renders a single player without a vs separator", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Drill",
        sportsCenterName: null,
        courtName: null,
        players: const ["Ana"],
        startTime: DateTime(2026, 6, 22, 9),
      ),
    );

    expect(name, "Drill - Ana - 2026-06-22 09:00");
  });

  test("keeps only the first two players when three or more are present", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Padel match",
        sportsCenterName: null,
        courtName: null,
        players: const ["Ana", "Luis", "Marc", "Eva"],
        startTime: DateTime(2026, 6, 22, 9),
      ),
    );

    expect(name, "Padel match - Ana vs Luis - 2026-06-22 09:00");
  });

  test("collapses a Custom activity preset to the Session prefix", () {
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Custom",
        sportsCenterName: null,
        courtName: "Court 4",
        players: const [],
        startTime: DateTime(2026, 6, 22, 9),
      ),
    );

    expect(name, "Session - Court 4 - 2026-06-22 09:00");
  });

  test("truncates names longer than the display cap and trims trailing space",
      () {
    final longCenter = "C" * 200;
    final name = sessionNamingService.defaultName(
      SessionNamingContext(
        activityPreset: "Training",
        sportsCenterName: longCenter,
        courtName: null,
        players: const [],
        startTime: DateTime(2026, 6, 22, 9),
      ),
    );

    expect(name.length,
        lessThanOrEqualTo(sessionNamingService.maxDisplayNameLength));
    expect(name.length, sessionNamingService.maxDisplayNameLength);
    expect(name, startsWith("Training - "));
    expect(name, isNot(endsWith(" ")));
  });
}
