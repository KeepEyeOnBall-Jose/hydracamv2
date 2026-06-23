# Human-Readable Session Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace primary GUID-based session labels with readable operator-facing session names, while keeping GUIDs as the internal API, storage, upload, and diagnostic identifiers.

**Architecture:** Add a display-name layer beside the existing `sessionGuid`, `sessionId`, and storage-directory identifiers. A pure naming service generates sensible defaults from activity preset, venue/court, players when available, and local start date/time; UI surfaces use the display name first and expose GUIDs only as technical diagnostics.

**Tech Stack:** Flutter/Dart, existing `SessionManager`, `CaptureSession`, `HydraCamApiService`, Material widgets, `flutter_test`.

---

## Scope Check

This is one connected UX/data-model feature. It touches session metadata,
session creation UI, and every current user-facing session list/detail surface.

Do not remove or weaken GUID usage. `sessionGuid` remains the service identity
for create/end/upload, master/slave transport, local folder lookup, gallery
matching, sync sidecars, automation, and logs. The new `displayName` is a human
alias only.

Do not depend on backend write support in the first app implementation. The
current mobile `sessions/create` request sends `SessionId` and `StartTime`; this
plan keeps that contract unchanged unless the backend explicitly accepts a
session-name field. Local metadata and app UI can still improve immediately.

## File Structure

- Create `lib/services/session_naming_service.dart`: pure default-name and
  sanitization logic.
- Modify `lib/models/capture_session.dart`: add `displayName` and
  `displayTitle`; keep `preferredIdentifier` for internal references.
- Modify `lib/services/session_manager.dart`: accept optional display names,
  persist/load `displayName` in `metadata.json`, and preserve names through
  restore and scan paths.
- Modify `lib/master/master_screen.dart`: add activity presets, generated
  session-name field, manual override handling, and readable snackbars.
- Modify `lib/widgets/session_info_widget.dart`: continue taking a display
  string, but tests should assert readable names rather than GUIDs.
- Modify `lib/screens/sessions_screen.dart`: prefer backend-provided
  display-name fields if present; otherwise fall back to a compact generated
  label instead of a GUID as the row title.
- Modify `lib/screens/previous_sessions_screen.dart`: show stored
  `CaptureSession.displayTitle` as the row title.
- Modify `lib/screens/session_details_screen.dart`: show display title in the
  app bar and metadata; move GUIDs to technical metadata labels.
- Modify `lib/screens/media_selection_screen.dart` and
  `lib/services/gallery_session_candidate_source.dart`: keep GUID-based matching
  but show `displayTitle` in candidate labels.
- Modify focused tests under `test/services`, `test/master`, `test/screens`,
  and `test/widgets`.

---

### Task 1: Add Pure Session Naming Rules

**Files:**
- Create: `lib/services/session_naming_service.dart`
- Test: `test/services/session_naming_service_test.dart`

- [ ] **Step 1: Write failing naming-service tests**

Create `test/services/session_naming_service_test.dart`:

```dart
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/session_naming_service.dart";

void main() {
  test("builds a default name from activity, location, players, and time", () {
    final name = SessionNamingService.defaultName(
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
    final name = SessionNamingService.defaultName(
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
    final name = SessionNamingService.defaultName(
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
      SessionNamingService.sanitizeCustomName(
        "  Finals\\nCourt   1   with   extra spacing  ",
      ),
      "Finals Court 1 with extra spacing",
    );
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/services/session_naming_service_test.dart
```

Expected: fail because `SessionNamingService` does not exist.

- [ ] **Step 3: Add the pure naming service**

Create `lib/services/session_naming_service.dart`:

```dart
class SessionNamingContext {
  const SessionNamingContext({
    required this.activityPreset,
    required this.sportsCenterName,
    required this.courtName,
    required this.players,
    required this.startTime,
  });

  final String activityPreset;
  final String? sportsCenterName;
  final String? courtName;
  final List<String> players;
  final DateTime startTime;
}

class SessionNamingService {
  static const List<String> activityPresets = [
    "Squash match",
    "Padel match",
    "Training",
    "Drill",
    "Warm-up",
    "Custom",
  ];

  static const String defaultActivityPreset = "Squash match";
  static const int maxDisplayNameLength = 96;

  static String defaultName(SessionNamingContext context) {
    final parts = <String>[];
    final activity = sanitizeCustomName(context.activityPreset);
    parts.add(activity.isEmpty ? "Session" : activity);

    final location = _locationLabel(
      context.sportsCenterName,
      context.courtName,
    );
    if (location.isNotEmpty) {
      parts.add(location);
    }

    final playerLabel = _playerLabel(context.players);
    if (playerLabel.isNotEmpty) {
      parts.add(playerLabel);
    }

    parts.add(_formatLocalDateTime(context.startTime));
    return _truncate(parts.join(" - "));
  }

  static String sanitizeCustomName(String rawName) {
    return rawName.trim().replaceAll(RegExp(r"\s+"), " ");
  }

  static String _locationLabel(String? sportsCenterName, String? courtName) {
    final center = sanitizeCustomName(sportsCenterName ?? "");
    final court = sanitizeCustomName(courtName ?? "");
    if (center.isEmpty) {
      return court;
    }
    if (court.isEmpty) {
      return center;
    }
    return "$center $court";
  }

  static String _playerLabel(List<String> players) {
    final cleanPlayers = players
        .map(sanitizeCustomName)
        .where((player) => player.isNotEmpty)
        .take(2)
        .toList();
    if (cleanPlayers.length == 2) {
      return "${cleanPlayers[0]} vs ${cleanPlayers[1]}";
    }
    if (cleanPlayers.length == 1) {
      return cleanPlayers.single;
    }
    return "";
  }

  static String _formatLocalDateTime(DateTime value) {
    final localValue = value.toLocal();
    final year = localValue.year.toString().padLeft(4, "0");
    final month = localValue.month.toString().padLeft(2, "0");
    final day = localValue.day.toString().padLeft(2, "0");
    final hour = localValue.hour.toString().padLeft(2, "0");
    final minute = localValue.minute.toString().padLeft(2, "0");
    return "$year-$month-$day $hour:$minute";
  }

  static String _truncate(String value) {
    if (value.length <= maxDisplayNameLength) {
      return value;
    }
    return value.substring(0, maxDisplayNameLength).trimRight();
  }
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
flutter test test/services/session_naming_service_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit the pure naming service**

Run:

```bash
git add lib/services/session_naming_service.dart test/services/session_naming_service_test.dart
git commit -m "feat: add session naming defaults"
```

### Task 2: Persist Display Names In Session Metadata

**Files:**
- Modify: `lib/models/capture_session.dart`
- Modify: `lib/services/session_manager.dart`
- Test: `test/services/session_manager_test.dart`

- [ ] **Step 1: Write failing metadata tests**

Add focused coverage in `test/services/session_manager_test.dart`:

```dart
test("persists and restores a human-readable display name", () async {
  final sessionManager = SessionManager.instance;
  sessionManager.startSession(
    "backend-guid",
    "legacy-session-id",
    deviceType: "Master",
    displayName: "Squash match - Sportwerk Court 2 - 2026-06-22 19:30",
  );

  await sessionManager.updateMetadata();

  final restored =
      await sessionManager.loadSessionMetadataSnapshot("backend-guid");

  expect(
    restored?.displayName,
    "Squash match - Sportwerk Court 2 - 2026-06-22 19:30",
  );
  expect(
    restored?.displayTitle,
    "Squash match - Sportwerk Court 2 - 2026-06-22 19:30",
  );
  expect(restored?.preferredIdentifier, "backend-guid");
});

test("display title falls back to the preferred identifier", () {
  final session = CaptureSession(
    sessionId: "legacy-session-id",
    sessionGuid: "backend-guid",
    startTime: DateTime(2026, 6, 22, 19, 30),
  );

  expect(session.displayTitle, "backend-guid");
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
flutter test test/services/session_manager_test.dart
```

Expected: fail because `displayName`, `displayTitle`, and the `startSession`
argument do not exist.

- [ ] **Step 3: Add display-name fields and persistence**

In `lib/models/capture_session.dart`, add a mutable display alias beside the
existing identifiers:

```dart
  /// Human-readable operator-facing name. This is not an API identifier.
  String? displayName;
```

Add it to the constructor:

```dart
    this.displayName,
```

Add a display-first title while keeping `preferredIdentifier` unchanged:

```dart
  String get displayTitle {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return preferredIdentifier;
  }
```

In `lib/services/session_manager.dart`, add optional `displayName` parameters
to `startCreatedSession`, `joinSession`, and `startSession`, pass the value into
`CaptureSession`, and include it in `_buildMetadataJson()`:

```dart
      "displayName": _currentSession!.displayName,
```

When loading metadata, parse `displayName` with a trim-and-empty-to-null helper:

```dart
  String? _optionalTrimmedString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
```

Pass that value into every `CaptureSession(...)` created from metadata.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
flutter test test/services/session_manager_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit the metadata contract**

Run:

```bash
git add lib/models/capture_session.dart lib/services/session_manager.dart test/services/session_manager_test.dart
git commit -m "feat: persist session display names"
```

### Task 3: Add Activity Presets And Generated Name Controls

**Files:**
- Modify: `lib/master/master_screen.dart`
- Modify: `test/master/master_screen_test.dart`

- [ ] **Step 1: Write failing master-screen tests**

Add coverage in `test/master/master_screen_test.dart` proving the setup UI
offers session naming before starting capture:

```dart
testWidgets("setup shows generated session naming controls", (tester) async {
  await tester.pumpWidget(const MaterialApp(home: MasterScreen()));
  await tester.pumpAndSettle();

  expect(find.text("Session name"), findsOneWidget);
  expect(find.text("Squash match"), findsOneWidget);
  expect(find.byKey(const ValueKey("sessionNameField")), findsOneWidget);
  expect(find.byKey(const ValueKey("resetGeneratedSessionNameButton")),
      findsOneWidget);
});
```

Add a create-session test or update the existing create-session test so the
created session receives the readable name:

```dart
expect(
  SessionManager.instance.currentSession?.displayName,
  startsWith("Squash match"),
);
```

- [ ] **Step 2: Run the focused master-screen tests and verify they fail**

Run:

```bash
flutter test test/master/master_screen_test.dart
```

Expected: fail because session naming controls do not exist.

- [ ] **Step 3: Add local setup state and generated-name behavior**

In `MasterScreenState`, add:

```dart
String selectedActivityPreset = SessionNamingService.defaultActivityPreset;
String? selectedSportsCenterName;
String? selectedCourtName;
final TextEditingController sessionNameController = TextEditingController();
bool sessionNameEditedManually = false;
```

Dispose the controller in `dispose()`.

When `CourtSelectionWidget` reports a selection, store both location fields:

```dart
selectedSportsCenterName = selection?.sportsCenterName;
selectedCourtName = selection?.courtName;
_refreshGeneratedSessionName();
```

Add a helper that regenerates only when the user has not manually edited the
field:

```dart
void _refreshGeneratedSessionName({bool force = false}) {
  if (sessionNameEditedManually && !force) {
    return;
  }
  sessionNameController.text = SessionNamingService.defaultName(
    SessionNamingContext(
      activityPreset: selectedActivityPreset,
      sportsCenterName: selectedSportsCenterName,
      courtName: selectedCourtName,
      players: const [],
      startTime: DateTime.now(),
    ),
  );
  sessionNameEditedManually = false;
}
```

Call `_refreshGeneratedSessionName(force: true)` from `initState()`.

- [ ] **Step 4: Add the visible controls**

In the no-active-session setup panel, add:

```dart
DropdownButtonFormField<String>(
  key: const ValueKey("activityPresetDropdown"),
  initialValue: selectedActivityPreset,
  decoration: const InputDecoration(
    labelText: "Activity",
    prefixIcon: Icon(Icons.sports_tennis_outlined),
  ),
  items: SessionNamingService.activityPresets
      .map(
        (preset) => DropdownMenuItem<String>(
          value: preset,
          child: Text(preset, overflow: TextOverflow.ellipsis),
        ),
      )
      .toList(),
  onChanged: (preset) {
    if (preset == null) {
      return;
    }
    setState(() {
      selectedActivityPreset = preset;
      _refreshGeneratedSessionName();
    });
  },
),
TextField(
  key: const ValueKey("sessionNameField"),
  controller: sessionNameController,
  decoration: InputDecoration(
    labelText: "Session name",
    prefixIcon: const Icon(Icons.edit_calendar_outlined),
    suffixIcon: IconButton(
      key: const ValueKey("resetGeneratedSessionNameButton"),
      icon: const Icon(Icons.auto_fix_high_outlined),
      tooltip: "Reset generated session name",
      onPressed: () => setState(() {
        _refreshGeneratedSessionName(force: true);
      }),
    ),
  ),
  onChanged: (_) {
    sessionNameEditedManually = true;
  },
),
```

- [ ] **Step 5: Pass the readable name into session creation**

In `_createSession`, derive a safe display name:

```dart
final displayName = SessionNamingService.sanitizeCustomName(
  sessionNameController.text,
);
```

Pass `displayName` into `SessionManager.instance.startCreatedSession(...)`.

Change the success snackbar from the raw GUID to the display name:

```dart
SnackBar(content: Text("Session created: $displayName"))
```

Keep `LogService` entries with the GUID for diagnostics.

- [ ] **Step 6: Run the focused master-screen tests**

Run:

```bash
flutter test test/master/master_screen_test.dart
```

Expected: pass.

- [ ] **Step 7: Commit the session setup UI**

Run:

```bash
git add lib/master/master_screen.dart test/master/master_screen_test.dart
git commit -m "feat: add session naming controls"
```

### Task 4: Replace Primary GUID Labels With Display Titles

**Files:**
- Modify: `lib/widgets/session_info_widget.dart`
- Modify: `lib/screens/sessions_screen.dart`
- Modify: `lib/screens/previous_sessions_screen.dart`
- Modify: `lib/screens/session_details_screen.dart`
- Modify: `lib/screens/media_selection_screen.dart`
- Test: `test/widgets/session_info_widget_test.dart`
- Test: `test/screens/sessions_screen_test.dart`
- Test: `test/screens/previous_sessions_screen_test.dart`
- Test: `test/screens/session_details_screen_test.dart`
- Test: `test/screens/media_selection_screen_test.dart`

- [ ] **Step 1: Write failing display-first tests**

Update existing expectations so primary labels use readable titles:

```dart
expect(find.text("Session: Squash match - Sportwerk Court 2"), findsOneWidget);
expect(find.text("Session: backend-session-guid"), findsNothing);
```

For technical metadata on details screens, assert GUIDs are not primary titles:

```dart
expect(find.text("Service GUID: backend-session-guid"), findsOneWidget);
expect(find.text("Legacy Session ID: legacy-session-id"), findsOneWidget);
```

- [ ] **Step 2: Run focused screen/widget tests and verify they fail**

Run:

```bash
flutter test test/widgets/session_info_widget_test.dart test/screens/sessions_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart test/screens/media_selection_screen_test.dart
```

Expected: fail because those surfaces still promote GUIDs.

- [ ] **Step 3: Display `CaptureSession.displayTitle` for stored sessions**

In `PreviousSessionsScreen`, change `_StoredSessionListItem.primaryIdentifier`
to:

```dart
String get primaryIdentifier {
  return session?.displayTitle ?? storageIdentifier;
}
```

In `SessionDetailsScreen`, change the app bar and metadata primary line to
`session.displayTitle`. Keep GUIDs visible only as technical details:

```dart
if (hasBackendGuid) Text("Service GUID: ${session.sessionGuid}"),
if (hasDistinctLegacySessionId)
  Text("Legacy Session ID: ${session.sessionId}"),
```

In `MediaSelectionScreen`, use `session.displayTitle` for candidate labels
while preserving `preferredIdentifier` for matching and loading.

- [ ] **Step 4: Display backend-provided names when available**

In `SessionsScreen`, add a helper:

```dart
String _sessionDisplayTitle(Map<String, dynamic> session) {
  for (final key in ["displayName", "name", "sessionName"]) {
    final value = session[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  final startTime = session["startTime"]?.toString().trim();
  if (startTime != null && startTime.isNotEmpty) {
    return "Session - $startTime";
  }
  return "Session";
}
```

Use this helper for row title and snackbar text. Continue using
`_primarySessionReference(session)` when joining/restoring a session.

- [ ] **Step 5: Run focused tests and verify they pass**

Run:

```bash
flutter test test/widgets/session_info_widget_test.dart test/screens/sessions_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart test/screens/media_selection_screen_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit display-first surfaces**

Run:

```bash
git add lib/widgets/session_info_widget.dart lib/screens/sessions_screen.dart lib/screens/previous_sessions_screen.dart lib/screens/session_details_screen.dart lib/screens/media_selection_screen.dart test/widgets/session_info_widget_test.dart test/screens/sessions_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart test/screens/media_selection_screen_test.dart
git commit -m "feat: show readable session titles"
```

### Task 5: Guard The Backend API Contract

**Files:**
- Modify: `lib/services/hydracam_api_service.dart`
- Test: `test/services/hydracam_api_service_test.dart`

- [ ] **Step 1: Add request-body regression coverage**

Add a test proving the initial implementation does not send unsupported
display-name fields to `sessions/create`:

```dart
test("createSession keeps the current backend body contract", () async {
  Map<String, dynamic>? requestBody;
  HydraCamApiService.configureHttpClient(
    MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        """{"guid":"backend-guid","sessionId":"legacy-id"}""",
        200,
      );
    }),
  );

  final result = await HydraCamApiService().createSession(
    "legacy-id",
    courtGuid: "court-guid",
    userGuid: "user-guid",
  );

  expect(result?.guid, "backend-guid");
  expect(requestBody, containsPair("SessionId", "legacy-id"));
  expect(requestBody, contains("StartTime"));
  expect(requestBody?.containsKey("DisplayName"), isFalse);
  expect(requestBody?.containsKey("displayName"), isFalse);
});
```

- [ ] **Step 2: Run the focused API tests**

Run:

```bash
flutter test test/services/hydracam_api_service_test.dart
```

Expected: pass.

- [ ] **Step 3: Parse backend display names if the service already returns them**

If `fetchSessions()` already returns a `displayName`, `name`, or `sessionName`
field in the raw session map, no model change is needed because `SessionsScreen`
reads the map. If future backend create responses include a name, extend
`HydraCamBackendSession` with optional `displayName` and route it into
`SessionManager.startCreatedSession(...)`.

- [ ] **Step 4: Commit API guardrails**

Run:

```bash
git add lib/services/hydracam_api_service.dart test/services/hydracam_api_service_test.dart
git commit -m "test: guard session create naming contract"
```

### Task 6: Verify And Record Evidence

**Files:**
- Modify: `docs/control/backlog-import.md`
- Evidence: `logs/verification-runs/<run>/`

- [ ] **Step 1: Run static formatting and analysis**

Run:

```bash
dart format lib/services/session_naming_service.dart lib/models/capture_session.dart lib/services/session_manager.dart lib/master/master_screen.dart lib/widgets/session_info_widget.dart lib/screens/sessions_screen.dart lib/screens/previous_sessions_screen.dart lib/screens/session_details_screen.dart lib/screens/media_selection_screen.dart test/services/session_naming_service_test.dart test/services/session_manager_test.dart test/master/master_screen_test.dart test/widgets/session_info_widget_test.dart test/screens/sessions_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart test/screens/media_selection_screen_test.dart
flutter analyze
```

Expected: formatting changes only in touched files; analyzer exits 0.

- [ ] **Step 2: Run focused and full tests**

Run:

```bash
flutter test test/services/session_naming_service_test.dart test/services/session_manager_test.dart test/master/master_screen_test.dart test/widgets/session_info_widget_test.dart test/screens/sessions_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart test/screens/media_selection_screen_test.dart test/services/hydracam_api_service_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 3: Run device-facing UI verification when hardware is available**

Run the default hardware UI smoke for the setup route on selected connected
Android devices:

```bash
scripts/run_hardware_ui_e2e.py --route setup --device <adb-serial>
```

Expected: evidence under `logs/verification-runs/<run>/`, no Flutter overflow
markers, and screenshots showing readable session-name controls without GUID
primary labels.

If iOS hardware is attached and responsive, install/launch the current checkout
and capture the setup or master route screenshot through the existing
automation bridge before claiming device-facing UI completion.

- [ ] **Step 4: Update the backlog note after implementation**

Append a dated verification note under the backlog item with the test commands,
hardware evidence path, and any backend-name contract decision.

- [ ] **Step 5: Commit documentation and evidence references**

Run:

```bash
git add docs/control/backlog-import.md logs/verification-runs/<run>
git commit -m "docs: record session naming verification"
```

## Acceptance Criteria

- Active-session, stored-session, fetched-session, media-selection, and
  session-detail surfaces show a readable display title as the primary label.
- GUIDs are still available where they are useful for diagnostics, logs,
  automation, uploads, local folder lookup, and backend calls, but they are not
  the primary operator-facing session name.
- Default names are generated from activity preset, venue/court, local date and
  time, and players when a player source is available.
- Operators can edit the generated name before creating the session and reset
  it back to an auto-generated value.
- `metadata.json` stores `displayName` without breaking old sessions that do
  not have that field.
- `sessions/create`, `sessions/end`, upload, WebSocket, and gallery-matching
  behavior continue to use stable identifiers.
- Focused tests, `flutter analyze`, and the relevant hardware UI smoke pass
  before the feature is marked done.
