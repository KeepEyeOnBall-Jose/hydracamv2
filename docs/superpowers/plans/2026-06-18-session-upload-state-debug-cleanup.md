# Session Upload State And Debug Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the local-session concept from HydraCam, replace it with one service-session model plus upload state, and make debug builds create labeled debug sessions whose uploaded local contents and service records can be cleaned up.

**Architecture:** A HydraCam session is always a service-created capture session with a service GUID. Upload progress is a computed state of that session's media: not uploaded, partially uploaded, or uploaded. Old `session_local-*` folders become legacy device media collections for recovery only, not sessions; debug session behavior is centralized in a policy service and a cleanup registry.

**Tech Stack:** Flutter/Dart, existing `SessionManager`, `HydraCamApiService`, `UploaderService`, `SharedPreferences`, `flutter_test`, Python static contract tests.

---

## Scope Check

This is one connected change because the rejected local-session split appears in the same runtime path, UI, tests, docs, and automation contracts. Do not split this into a separate UI-only cleanup: leaving `backendCreated`, `localOnly`, or `start_local_session` behavior intact would preserve the rejected model under a different label.

The backend service currently exposes create, end, fetch, and upload through the mobile API wrapper. Existing evidence also shows the web service has a non-API delete form at `/HydraCam/DeleteSession` using a numeric id. The mobile app already parses `HydraCamBackendSession.numericId`; the cleanup mechanism should preserve that id and add a typed deletion client contract, with tests against a fake HTTP client. Live service deletion proof requires the service to expose an authenticated delete API or an approved admin cleanup lane.

## File Structure

- Create `lib/models/session_upload_state.dart`: upload-state enum and summary calculator.
- Modify `lib/models/capture_session.dart`: remove `backendCreated`; add optional `debugSession`; keep `preferredIdentifier`.
- Create `lib/services/debug_session_policy.dart`: decides debug session id prefixing and local cleanup behavior from build mode.
- Create `lib/services/debug_session_registry.dart`: records debug session refs created by debug builds for later service cleanup.
- Modify `lib/services/session_manager.dart`: remove local/backend-created split, validate service GUIDs, persist debug flag and numeric service id, classify legacy `local-*` folders as legacy media.
- Modify `lib/services/hydracam_api_service.dart`: add delete-debug-session contract and method.
- Modify `lib/services/uploader_service.dart`: upload based on service GUID only; delete uploaded debug media regardless of normal setting.
- Modify `lib/master/master_screen.dart`: create labeled debug session ids in debug builds; remove `localOnly`; replace button labels.
- Modify `lib/slave/slave_client.dart`: remove "local session" log/status wording.
- Modify `lib/screens/previous_sessions_screen.dart` and `lib/screens/session_details_screen.dart`: present device-stored service sessions and legacy media without "local session" language; show computed upload state.
- Modify `scripts/test_no_local_sessions.py`: forbid local-session runtime leftovers and UI text.
- Modify docs under `AGENTS.md` and `docs/control/`: replace local-session terminology with service session, device media, or legacy media collection.
- Modify focused tests under `test/services`, `test/master`, `test/slave`, and `test/screens`.

---

### Task 1: Add Computed Session Upload State

**Files:**
- Create: `lib/models/session_upload_state.dart`
- Modify: `lib/models/capture_session.dart`
- Test: `test/models/session_upload_state_test.dart`

- [x] **Step 1: Write the failing upload-state tests**

Create `test/models/session_upload_state_test.dart`:

```dart
import "package:flutter_test/flutter_test.dart";
import "package:sport_cam_sync/models/capture_session.dart";
import "package:sport_cam_sync/models/captured_photo.dart";
import "package:sport_cam_sync/models/captured_video.dart";
import "package:sport_cam_sync/models/session_upload_state.dart";

void main() {
  CapturedPhoto photo(String path, {required bool uploaded}) {
    return CapturedPhoto(
      photoPath: path,
      slaveDeviceId: "device-one",
      captureDate: DateTime(2026, 6, 18, 10),
      receivedDate: DateTime(2026, 6, 18, 10, 0, 1),
      isUploaded: uploaded,
    );
  }

  CapturedVideo video(String path, {required bool uploaded}) {
    return CapturedVideo(
      videoPath: path,
      slaveDeviceId: "device-one",
      startRecordingDate: DateTime(2026, 6, 18, 10, 1),
      endRecordingDate: DateTime(2026, 6, 18, 10, 1, 10),
      receivedDate: DateTime(2026, 6, 18, 10, 1, 11),
      isUploaded: uploaded,
    );
  }

  test("summarizes an empty session as not uploaded", () {
    final session = CaptureSession(
      sessionId: "empty-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.notUploaded);
    expect(summary.totalCount, 0);
    expect(summary.uploadedCount, 0);
    expect(summary.pendingCount, 0);
  });

  test("summarizes a session with no uploaded media as not uploaded", () {
    final session = CaptureSession(
      sessionId: "new-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: false)],
      capturedVideos: [video("one.mp4", uploaded: false)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.notUploaded);
    expect(summary.totalCount, 2);
    expect(summary.uploadedCount, 0);
    expect(summary.pendingCount, 2);
    expect(summary.label, "Not uploaded");
  });

  test("summarizes a mixed session as partially uploaded", () {
    final session = CaptureSession(
      sessionId: "mixed-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: true)],
      capturedVideos: [video("one.mp4", uploaded: false)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.partiallyUploaded);
    expect(summary.uploadedCount, 1);
    expect(summary.pendingCount, 1);
    expect(summary.label, "Partially uploaded");
  });

  test("summarizes a complete session as uploaded", () {
    final session = CaptureSession(
      sessionId: "complete-session",
      sessionGuid: "service-guid",
      startTime: DateTime(2026, 6, 18, 10),
      capturedPhotos: [photo("one.jpg", uploaded: true)],
      capturedVideos: [video("one.mp4", uploaded: true)],
    );

    final summary = summarizeSessionUpload(session);

    expect(summary.state, SessionUploadState.uploaded);
    expect(summary.uploadedCount, 2);
    expect(summary.pendingCount, 0);
    expect(summary.label, "Uploaded");
  });
}
```

- [x] **Step 2: Run the failing test**

Run:

```bash
flutter test test/models/session_upload_state_test.dart
```

Expected: FAIL because `session_upload_state.dart` does not exist.

- [x] **Step 3: Implement upload-state model**

Create `lib/models/session_upload_state.dart`:

```dart
import "capture_session.dart";

enum SessionUploadState {
  notUploaded,
  partiallyUploaded,
  uploaded,
}

class SessionUploadSummary {
  const SessionUploadSummary({
    required this.state,
    required this.totalCount,
    required this.uploadedCount,
    required this.pendingCount,
  });

  final SessionUploadState state;
  final int totalCount;
  final int uploadedCount;
  final int pendingCount;

  String get label {
    return switch (state) {
      SessionUploadState.notUploaded => "Not uploaded",
      SessionUploadState.partiallyUploaded => "Partially uploaded",
      SessionUploadState.uploaded => "Uploaded",
    };
  }
}

SessionUploadSummary summarizeSessionUpload(CaptureSession session) {
  final media = [
    ...session.capturedPhotos,
    ...session.capturedVideos,
  ];
  final totalCount = media.length;
  final uploadedCount = media.where((item) => item.isUploaded).length;
  final pendingCount = totalCount - uploadedCount;

  final SessionUploadState state;
  if (totalCount == 0 || uploadedCount == 0) {
    state = SessionUploadState.notUploaded;
  } else if (uploadedCount == totalCount) {
    state = SessionUploadState.uploaded;
  } else {
    state = SessionUploadState.partiallyUploaded;
  }

  return SessionUploadSummary(
    state: state,
    totalCount: totalCount,
    uploadedCount: uploadedCount,
    pendingCount: pendingCount,
  );
}
```

- [x] **Step 4: Run the test**

Run:

```bash
flutter test test/models/session_upload_state_test.dart
```

Expected: PASS.

---

### Task 2: Remove Local/Backend-Created Session Split From Runtime State

**Files:**
- Modify: `lib/models/capture_session.dart`
- Modify: `lib/services/session_manager.dart`
- Modify: `test/services/session_manager_test.dart`
- Modify: `test/services/uploader_service_test.dart`

- [x] **Step 1: Write tests for service-session validation and legacy folder classification**

In `test/services/session_manager_test.dart`, replace tests named `startBackendSession rejects local session GUIDs` and `joinBackendSession rejects local session GUIDs` with:

```dart
test("startCreatedSession rejects non-service GUIDs", () {
  expect(
    () => sessionManager.startCreatedSession(
      const HydraCamBackendSession(
        guid: "local-backend-guid",
        sessionId: "debug-request",
      ),
      deviceType: "Master",
    ),
    throwsArgumentError,
  );
});

test("joinSession rejects non-service GUIDs", () {
  expect(
    () => sessionManager.joinSession(
      "local-slave-guid",
      "slave-session",
      deviceType: "Slave",
    ),
    throwsArgumentError,
  );
});
```

Add:

```dart
test("canUploadCurrentSession requires an active service GUID", () {
  sessionManager.startSession(
    "service-session-guid",
    "session-id",
    deviceType: "Master",
  );

  expect(sessionManager.canUploadCurrentSession, isTrue);
});
```

In `test/services/uploader_service_test.dart`, replace `addMediaToQueue refuses media when session is not backend-created` with:

```dart
test("addMediaToQueue refuses media when no service session is active", () async {
  await SessionManager.instance.endSession();
  final photoFile = File("${tempDir.path}/unattached-media.jpg")
    ..writeAsBytesSync(_validJpegBytes());
  final photo = CapturedPhoto(
    photoPath: photoFile.path,
    slaveDeviceId: "diagnostic-device",
    captureDate: DateTime(2026, 6, 18, 3),
    receivedDate: DateTime(2026, 6, 18, 3, 0, 1),
  );

  await uploaderService.addMediaToQueue(photo);

  expect(uploaderService.queueLength, 0);
  expect(photo.isUploaded, isFalse);
  expect(photo.uploadFailureReason, contains("no active service session"));
  expect(
    LogService.instance.logs.map((entry) => entry["message"]),
    contains(contains("no active service session")),
  );
});
```

- [x] **Step 2: Run focused tests and verify failure**

Run:

```bash
flutter test test/services/session_manager_test.dart test/services/uploader_service_test.dart
```

Expected: FAIL because `startCreatedSession`, `joinSession`, and new messages do not exist yet.

- [x] **Step 3: Update `CaptureSession`**

In `lib/models/capture_session.dart`, replace the `backendCreated` field with:

```dart
  /// Whether this service-created session is a debug build artifact.
  final bool debugSession;

  /// Numeric service id returned by the current MoBo API when available.
  final int? serviceNumericId;
```

Update the constructor parameters:

```dart
    this.debugSession = false,
    this.serviceNumericId,
```

Remove all `backendCreated` constructor use.

- [x] **Step 4: Update `SessionManager` public session API**

In `lib/services/session_manager.dart`, replace `startBackendSession`, `joinBackendSession`, `startSession`, and uploadability getters with:

```dart
  bool get canUploadCurrentSession =>
      _currentSession != null && isServiceSessionGuid(_sessionGuid);
  bool get isCurrentSessionDebug => _currentSession?.debugSession ?? false;

  static bool isServiceSessionGuid(String? sessionGuid) {
    final normalizedSessionGuid = sessionGuid?.trim() ?? "";
    return normalizedSessionGuid.isNotEmpty &&
        !normalizedSessionGuid.startsWith("local-");
  }

  void startCreatedSession(
    api.HydraCamBackendSession session, {
    required String deviceType,
    bool debugSession = false,
  }) {
    startSession(
      session.guid,
      session.sessionId,
      deviceType: deviceType,
      debugSession: debugSession,
      serviceNumericId: session.numericId,
    );
  }

  void joinSession(
    String sessionGuid,
    String? sessionId, {
    required String deviceType,
    bool debugSession = false,
    int? serviceNumericId,
  }) {
    startSession(
      sessionGuid,
      sessionId ?? sessionGuid,
      deviceType: deviceType,
      debugSession: debugSession,
      serviceNumericId: serviceNumericId,
    );
  }

  @visibleForTesting
  void startSession(
    String sessionGuid,
    String? sessionId, {
    required String deviceType,
    bool debugSession = false,
    int? serviceNumericId,
  }) {
    final normalizedSessionGuid = _validateServiceSessionGuid(sessionGuid);
    if (_currentSession != null && _sessionGuid == normalizedSessionGuid) {
      _deviceType = deviceType;
      LogService.instance.registerLog(
          "Session already active with GUID: $_sessionGuid. Preserving existing media on rejoin as $_deviceType.");
      notifyListeners();
      return;
    }

    UploaderService().reset();

    _sessionGuid = normalizedSessionGuid;
    _deviceType = deviceType;
    _currentSession = CaptureSession(
      sessionId: sessionId ?? normalizedSessionGuid,
      sessionGuid: normalizedSessionGuid,
      startTime: DateTime.now(),
      debugSession: debugSession,
      serviceNumericId: serviceNumericId,
    );

    LogService.instance.registerLog(
        "Session started with GUID: $_sessionGuid on device type: $_deviceType");
    notifyListeners();
  }
```

Replace `_validateSessionGuid` with:

```dart
  String _validateServiceSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    if (normalizedSessionGuid.isEmpty) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "Service session GUID is required.",
      );
    }
    if (!isServiceSessionGuid(normalizedSessionGuid)) {
      throw ArgumentError.value(
        sessionGuid,
        "sessionGuid",
        "A service-created session is required before capture or upload.",
      );
    }
    return normalizedSessionGuid;
  }
```

Remove `_isBackendCreated`, `isCurrentSessionBackendCreated`, `_metadataSessionIsBackendCreated`, `_metadataMarksBackendCreated`, and `_looksLikeBackendSessionGuid`.

- [x] **Step 5: Persist debug metadata without `backendCreated`**

In `_buildMetadataJson`, replace the old body with:

```dart
    return {
      "sessionId": _currentSession!.sessionId,
      "sessionGuid": _sessionGuid,
      "debugSession": _currentSession!.debugSession,
      "serviceNumericId": _currentSession!.serviceNumericId,
      "startTime": _currentSession!.startTime.toIso8601String(),
      "endTime": _currentSession!.endTime?.toIso8601String(),
      "deviceType": _deviceType,
      "photos": _currentSession!.capturedPhotos.map(_photoToJson).toList(),
      "videos": _currentSession!.capturedVideos.map(_videoToJson).toList(),
    };
```

In metadata loaders, pass:

```dart
        debugSession: metadata["debugSession"] == true,
        serviceNumericId: _asNullableInt(metadata["serviceNumericId"]),
```

- [x] **Step 6: Keep old `local-*` folders as legacy media, not sessions**

In `scanAndReconstructSessions`, before metadata repair or reconstruction, add:

```dart
      final sessionGuid = _sessionIdentifierFromDirectory(dir);
      if (!isServiceSessionGuid(sessionGuid)) {
        LogService.instance.registerLog(
            "Skipping legacy device media folder while scanning service sessions: $sessionGuid");
        continue;
      }
```

In `restoreSessionFromMetadata`, replace the backend-created metadata check with:

```dart
    if (!isServiceSessionGuid(restoredSessionGuid)) {
      throw StateError(
          "Stored media $restoredSessionGuid is not attached to a service session and cannot be restored for upload.");
    }
```

- [x] **Step 7: Update call sites**

Replace:

```dart
SessionManager.instance.startBackendSession(...)
SessionManager.instance.joinBackendSession(...)
```

with:

```dart
SessionManager.instance.startCreatedSession(...)
SessionManager.instance.joinSession(...)
```

Update `test/test_utils/mock_services.dart` to remove `backendCreated` from helpers.

- [x] **Step 8: Run focused tests**

Run:

```bash
flutter test test/services/session_manager_test.dart test/services/uploader_service_test.dart test/slave/slave_client_registration_test.dart test/master/master_screen_test.dart
```

Expected: PASS.

---

### Task 3: Replace User-Facing Local Session UI And "Or..." Copy

**Files:**
- Modify: `lib/master/master_screen.dart`
- Modify: `lib/screens/previous_sessions_screen.dart`
- Modify: `lib/screens/session_details_screen.dart`
- Modify: `test/master/master_screen_test.dart`
- Modify: `test/screens/previous_sessions_screen_test.dart`
- Modify: `test/screens/session_details_screen_test.dart`

- [x] **Step 1: Add failing UI text assertions**

In `test/master/master_screen_test.dart`, add or update a no-active-session UI test:

```dart
testWidgets("start area uses service-session language", (tester) async {
  await tester.pumpWidget(const MaterialApp(home: MasterScreen()));
  await tester.pumpAndSettle();

  expect(find.text("Start Session"), findsOneWidget);
  expect(find.text("Join Existing Session"), findsOneWidget);
  expect(find.text("Review Stored Media"), findsOneWidget);
  expect(find.textContaining("Or..."), findsNothing);
  expect(find.textContaining("Local Sessions"), findsNothing);
});
```

In `test/screens/previous_sessions_screen_test.dart`, assert:

```dart
expect(find.text("Stored Media"), findsOneWidget);
expect(find.textContaining("Local"), findsNothing);
```

In `test/screens/session_details_screen_test.dart`, assert upload state appears:

```dart
expect(find.text("Upload State: Partially uploaded"), findsOneWidget);
```

- [x] **Step 2: Run failing UI tests**

Run:

```bash
flutter test test/master/master_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart
```

Expected: FAIL because the current UI still has `Or... Load a Previous One`, `View Local Sessions`, and no upload-state row.

- [x] **Step 3: Update master screen labels**

In `lib/master/master_screen.dart`, replace:

```dart
label: const Text("Or... Load a Previous One"),
```

with:

```dart
label: const Text("Join Existing Session"),
```

Replace:

```dart
label: const Text("View Local Sessions"),
```

with:

```dart
label: const Text("Review Stored Media"),
```

- [x] **Step 4: Update stored media screen title and empty state**

In `lib/screens/previous_sessions_screen.dart`, replace:

```dart
title: const Text("Previous Sessions"),
```

with:

```dart
title: const Text("Stored Media"),
```

Replace:

```dart
return const Center(child: Text("No previous sessions found."));
```

with:

```dart
return const Center(child: Text("No stored media found."));
```

Replace list titles:

```dart
title: Text("Session: $sessionId"),
```

with:

```dart
title: Text("Service session: $sessionId"),
```

- [x] **Step 5: Show upload state in session details**

Import:

```dart
import "../models/session_upload_state.dart";
```

In `_buildSessionMetadata`, before media counts, add:

```dart
                Text("Upload State: ${summarizeSessionUpload(session).label}"),
```

- [x] **Step 6: Run UI tests**

Run:

```bash
flutter test test/master/master_screen_test.dart test/screens/previous_sessions_screen_test.dart test/screens/session_details_screen_test.dart
```

Expected: PASS.

---

### Task 4: Remove Runtime Automation Leftovers For Local-Only Sessions

**Files:**
- Modify: `lib/master/master_screen.dart`
- Modify: `lib/slave/slave_client.dart`
- Modify: `scripts/test_no_local_sessions.py`
- Modify: `test/slave/slave_client_registration_test.dart`
- Modify: `test/master/master_screen_test.dart`

- [x] **Step 1: Strengthen the static no-local-session test**

In `scripts/test_no_local_sessions.py`, replace `RUNTIME_FILES` with:

```python
RUNTIME_FILES = [
    pathlib.Path("lib"),
    pathlib.Path("scripts/ios_capture_repro.py"),
    pathlib.Path("scripts/run_parallel_device_matrix.py"),
    pathlib.Path("scripts/run_rotating_master_slave_matrix.py"),
]
```

Replace the file read loop with:

```python
                paths = (
                    relative_path.rglob("*.dart")
                    if relative_path.is_dir()
                    else [relative_path]
                )
                for path in paths:
                    text = (REPO_ROOT / path).read_text()
                    for literal in FORBIDDEN_LITERALS:
                        self.assertNotIn(literal, text, path)
                    for pattern in FORBIDDEN_LOCAL_GUID_PATTERNS:
                        self.assertIsNone(pattern.search(text), path)
                    for pattern in FORBIDDEN_LOCAL_ONLY_OBFUSCATION_PATTERNS:
                        self.assertIsNone(pattern.search(text), path)
```

Replace `test_master_rejects_legacy_local_only_payload_explicitly` with:

```python
    def test_master_does_not_reference_local_only_payloads(self):
        text = (REPO_ROOT / "lib/master/master_screen.dart").read_text()

        self.assertNotIn('"localOnly"', text)
        self.assertNotIn("backend sessions are mandatory", text)
```

- [x] **Step 2: Run failing static test**

Run:

```bash
python3 scripts/test_no_local_sessions.py
```

Expected: FAIL because `master_screen.dart` still references `localOnly`, and slave logs still say `local session`.

- [x] **Step 3: Remove `localOnly` branch from automation start**

In `lib/master/master_screen.dart`, replace the `start_session` handler with:

```dart
      "start_session": (payload) async {
        await _createSession(
          suppressSnackbars: true,
          skipCourtSelectionWarning: true,
          overrideCourtGuid: payload["courtGuid"] as String?,
          overrideSessionId: payload["sessionId"] as String?,
        );
        return AutomationBridge.instance.buildSessionSnapshot();
      },
```

- [x] **Step 4: Replace slave wording**

In `lib/slave/slave_client.dart`, replace conflict log/status text with:

```dart
      LogService.instance
          .registerLog("Master session conflict: keeping active session "
              "$activeSessionGuid instead of joining $sessionGuid.");
      _statusStreamController
          .add("Master reported a different session. Active session kept.");
```

Replace no-session log/status text with:

```dart
      LogService.instance.registerLog(
          "Master reported no active session; keeping active session "
          "$activeSessionGuid until explicit sessionEnded.");
      _statusStreamController
          .add("Master has no active session. Active session kept.");
```

- [x] **Step 5: Run static and behavior tests**

Run:

```bash
python3 scripts/test_no_local_sessions.py
flutter test test/slave/slave_client_registration_test.dart test/master/master_screen_test.dart
```

Expected: PASS.

---

### Task 5: Make Debug Builds Create Labeled Debug Service Sessions

**Files:**
- Create: `lib/services/debug_session_policy.dart`
- Modify: `lib/master/master_screen.dart`
- Modify: `lib/services/session_manager.dart`
- Test: `test/services/debug_session_policy_test.dart`
- Modify: `test/master/master_screen_test.dart`

- [x] **Step 1: Write debug policy tests**

Create `test/services/debug_session_policy_test.dart`:

```dart
import "package:flutter_test/flutter_test.dart";
import "package:sport_cam_sync/services/debug_session_policy.dart";

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
```

- [x] **Step 2: Run failing policy test**

Run:

```bash
flutter test test/services/debug_session_policy_test.dart
```

Expected: FAIL because `debug_session_policy.dart` does not exist.

- [x] **Step 3: Implement debug session policy**

Create `lib/services/debug_session_policy.dart`:

```dart
import "package:flutter/foundation.dart";

class DebugSessionPolicy {
  DebugSessionPolicy({
    bool? debugBuild,
    DateTime Function()? now,
    String? platformLabel,
  })  : _debugBuild = debugBuild ?? kDebugMode,
        _now = now ?? DateTime.now,
        _platformLabel = platformLabel ?? defaultTargetPlatform.name;

  final bool _debugBuild;
  final DateTime Function() _now;
  final String _platformLabel;

  bool get debugBuild => _debugBuild;

  String defaultSessionId() {
    final now = _now().toUtc();
    if (!_debugBuild) {
      return now.toIso8601String();
    }
    final compactTimestamp = now
        .toIso8601String()
        .replaceAll("-", "")
        .replaceAll(":", "")
        .replaceAll(".000", "");
    return "debug-$_platformLabel-$compactTimestamp";
  }

  bool shouldDeleteUploadedLocalMedia({required bool debugSession}) {
    return _debugBuild && debugSession;
  }
}
```

- [x] **Step 4: Use policy in master session creation**

In `lib/master/master_screen.dart`, add:

```dart
import "../services/debug_session_policy.dart";
```

Add a field to `_MasterScreenState`:

```dart
  final DebugSessionPolicy _debugSessionPolicy = DebugSessionPolicy();
```

Replace:

```dart
final sessionId = overrideSessionId ?? DateTime.now().toIso8601String();
```

with:

```dart
final sessionId = overrideSessionId ?? _debugSessionPolicy.defaultSessionId();
final debugSession =
    overrideSessionId == null && _debugSessionPolicy.debugBuild;
```

When starting the session, pass:

```dart
        SessionManager.instance.startCreatedSession(
          backendSession,
          deviceType: "Master",
          debugSession: debugSession,
        );
```

- [x] **Step 5: Persist and expose debug flag**

Use the `debugSession` metadata changes from Task 2. Add a `SessionManager.isCurrentSessionDebug` assertion in `test/master/master_screen_test.dart` by injecting a fake `DebugSessionPolicy` if the existing test structure supports it; otherwise keep coverage in `debug_session_policy_test.dart` and `session_manager_test.dart`.

- [x] **Step 6: Run focused tests**

Run:

```bash
flutter test test/services/debug_session_policy_test.dart test/master/master_screen_test.dart test/services/session_manager_test.dart
```

Expected: PASS.

---

### Task 6: Force Local Content Deletion For Uploaded Debug Sessions

**Files:**
- Modify: `lib/services/session_manager.dart`
- Modify: `lib/services/uploader_service.dart`
- Modify: `test/services/uploader_service_test.dart`

- [x] **Step 1: Write failing debug deletion test**

In `test/services/uploader_service_test.dart`, add:

```dart
test("debug session upload deletes local media even when user setting is false",
    () async {
  await SettingsService.setDeleteLocalAfterUpload(false);
  SessionManager.instance.startSession(
    "debug-service-session-guid",
    "debug-android-20260618T123456Z",
    deviceType: "Master",
    debugSession: true,
  );
  final photoFile = File("${tempDir.path}/debug-photo.jpg")
    ..writeAsBytesSync(_validJpegBytes());
  final photo = CapturedPhoto(
    photoPath: photoFile.path,
    slaveDeviceId: "debug-device",
    captureDate: DateTime(2026, 6, 18, 12, 35),
    receivedDate: DateTime(2026, 6, 18, 12, 35, 1),
  );

  await SessionManager.instance.addPhoto(photo);
  await uploaderService.startUploadingManually();

  expect(photo.isUploaded, isTrue);
  expect(photoFile.existsSync(), isFalse);
});
```

- [x] **Step 2: Run failing test**

Run:

```bash
flutter test test/services/uploader_service_test.dart --plain-name "debug session upload deletes local media even when user setting is false"
```

Expected: FAIL because deletion only follows the user setting.

- [x] **Step 3: Add session-aware delete decision**

In `lib/services/session_manager.dart`, add:

```dart
  Future<bool> shouldDeleteUploadedFile() async {
    if (isCurrentSessionDebug) {
      return true;
    }
    return SettingsService.getDeleteLocalAfterUpload();
  }
```

Replace `deleteFileIfAllowed` body with:

```dart
    final shouldDelete = await shouldDeleteUploadedFile();
    if (!shouldDelete) {
      return;
    }
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
        LogService.instance.registerLog("Deleted uploaded local file: $filePath");
      } catch (e) {
        LogService.instance
            .registerLog("Failed to delete uploaded local file: $filePath, error: $e");
      }
    } else {
      LogService.instance
          .registerLog("Uploaded local file already missing: $filePath");
    }
```

- [x] **Step 4: Run focused uploader test**

Run:

```bash
flutter test test/services/uploader_service_test.dart --plain-name "debug session upload deletes local media even when user setting is false"
```

Expected: PASS.

---

### Task 7: Prepare Service Cleanup Mechanism For Debug Sessions

**Files:**
- Create: `lib/services/debug_session_registry.dart`
- Modify: `lib/services/hydracam_api_service.dart`
- Modify: `lib/master/master_screen.dart`
- Test: `test/services/debug_session_registry_test.dart`
- Modify: `test/services/hydracam_api_service_test.dart`

- [x] **Step 1: Write registry tests**

Create `test/services/debug_session_registry_test.dart`:

```dart
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:sport_cam_sync/services/debug_session_registry.dart";

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
```

- [x] **Step 2: Implement registry**

Create `lib/services/debug_session_registry.dart`:

```dart
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

@immutable
class DebugSessionRef {
  const DebugSessionRef({
    required this.sessionGuid,
    required this.sessionId,
    this.serviceNumericId,
  });

  final String sessionGuid;
  final String sessionId;
  final int? serviceNumericId;

  Map<String, dynamic> toJson() {
    return {
      "sessionGuid": sessionGuid,
      "sessionId": sessionId,
      "serviceNumericId": serviceNumericId,
    };
  }

  factory DebugSessionRef.fromJson(Map<String, dynamic> json) {
    return DebugSessionRef(
      sessionGuid: json["sessionGuid"].toString(),
      sessionId: json["sessionId"].toString(),
      serviceNumericId: json["serviceNumericId"] is int
          ? json["serviceNumericId"] as int
          : int.tryParse(json["serviceNumericId"]?.toString() ?? ""),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DebugSessionRef &&
        other.sessionGuid == sessionGuid &&
        other.sessionId == sessionId &&
        other.serviceNumericId == serviceNumericId;
  }

  @override
  int get hashCode => Object.hash(sessionGuid, sessionId, serviceNumericId);
}

class DebugSessionRegistry {
  static const String _key = "debugSessionRegistry";

  Future<List<DebugSessionRef>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return raw
        .map((entry) => DebugSessionRef.fromJson(
              jsonDecode(entry) as Map<String, dynamic>,
            ))
        .toList();
  }

  Future<void> record(DebugSessionRef ref) async {
    final refs = await list();
    final updated = [
      ...refs.where((item) => item.sessionGuid != ref.sessionGuid),
      ref,
    ];
    await _write(updated);
  }

  Future<void> remove(String sessionGuid) async {
    final refs = await list();
    await _write(
      refs.where((item) => item.sessionGuid != sessionGuid).toList(),
    );
  }

  Future<void> _write(List<DebugSessionRef> refs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      refs.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
```

- [x] **Step 3: Add API contract test**

In `test/services/hydracam_api_service_test.dart`, add a fake HTTP test:

```dart
test("deleteDebugSession posts debug delete request with service identifiers",
    () async {
  final client = RecordingHttpClient(
    response: http.Response("{}", 200),
  );
  HydraCamApiService.configureHttpClientForTests(client);

  final deleted = await HydraCamApiService().deleteDebugSession(
    sessionGuid: "debug-guid",
    serviceNumericId: 456,
  );

  expect(deleted, isTrue);
  expect(client.lastRequest!.method, "POST");
  expect(client.lastRequest!.url.path, "/api/sessions/debug/delete");
  expect(client.lastRequest!.url.queryParameters["sessionGuid"], "debug-guid");
  expect(client.lastRequest!.url.queryParameters["id"], "456");
});
```

- [x] **Step 4: Add API delete method**

In `HydraCamSessionContract`, add:

```dart
  static const String deleteDebugSessionEndpoint = "sessions/debug/delete";
  static const String querySessionNumericId = "id";
```

In `HydraCamApiService`, add:

```dart
  Future<bool> deleteDebugSession({
    required String sessionGuid,
    int? serviceNumericId,
  }) async {
    try {
      final response = await _post(
        hydracamApiEndpoint(
          HydraCamSessionContract.deleteDebugSessionEndpoint,
          queryParameters: {
            HydraCamSessionContract.querySessionGuid: sessionGuid,
            HydraCamSessionContract.querySessionNumericId:
                serviceNumericId?.toString(),
          },
        ),
        {},
      );
      if (response != null) {
        LogService.instance
            .registerLog("Debug session deleted from service: $sessionGuid");
        return true;
      }
      LogService.instance
          .registerLog("Failed to delete debug session from service: $sessionGuid");
      return false;
    } catch (e) {
      LogService.instance
          .registerLog("Error deleting debug session from service: $e");
      return false;
    }
  }
```

- [x] **Step 5: Record debug sessions after creation**

In `lib/master/master_screen.dart`, after successful debug session creation:

```dart
        if (debugSession) {
          await DebugSessionRegistry().record(
            DebugSessionRef(
              sessionGuid: backendSession.guid,
              sessionId: backendSession.sessionId,
              serviceNumericId: backendSession.numericId,
            ),
          );
        }
```

Import:

```dart
import "../services/debug_session_registry.dart";
```

- [x] **Step 6: Add cleanup script entrypoint**

Create `scripts/cleanup_debug_sessions.dart` only if the repo already runs Dart scripts in CI; otherwise use a Python static plan in `scripts/cleanup_debug_sessions.py`. Prefer Python for this repo's existing script style:

```python
#!/usr/bin/env python3
"""Delete HydraCam debug sessions once the service debug-delete endpoint exists."""

import argparse
import json
import pathlib
import urllib.parse
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="https://hydracam.azurewebsites.net/api")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--bearer-token", required=True)
    args = parser.parse_args()

    refs = json.loads(pathlib.Path(args.manifest).read_text())
    for ref in refs:
        query = urllib.parse.urlencode(
            {
                "sessionGuid": ref["sessionGuid"],
                "id": ref.get("serviceNumericId") or "",
            }
        )
        request = urllib.request.Request(
            f"{args.base_url.rstrip('/')}/sessions/debug/delete?{query}",
            method="POST",
            headers={"Authorization": f"Bearer {args.bearer_token}"},
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            print(f"{ref['sessionGuid']}: {response.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Add `scripts/test_cleanup_debug_sessions.py` with a static contract:

```python
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("cleanup_debug_sessions.py")


class CleanupDebugSessionsContractTest(unittest.TestCase):
    def test_script_targets_debug_delete_endpoint(self):
        source = SCRIPT.read_text()
        self.assertIn("sessions/debug/delete", source)
        self.assertIn("sessionGuid", source)
        self.assertIn("serviceNumericId", source)
        self.assertIn("Authorization", source)


if __name__ == "__main__":
    unittest.main()
```

- [x] **Step 7: Run cleanup tests**

Run:

```bash
flutter test test/services/debug_session_registry_test.dart test/services/hydracam_api_service_test.dart
python3 scripts/test_cleanup_debug_sessions.py
```

Expected: PASS locally with mocked HTTP/static script coverage. Live deletion remains unclaimed until the service endpoint exists and credentials are supplied.

---

### Task 8: Update Docs And Control Plane Terminology

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/control/hydracam-mobo-media-timeline-merge-plan.md`
- Modify: `docs/control/device-relationship-fsm.md`
- Modify: `docs/control/user-flow-tracker.md`
- Modify: `docs/control/backlog-import.md`
- Modify: `docs/control/status-and-roadmap.md`

- [x] **Step 1: Replace rejected terminology**

Run:

```bash
rg -n "local session|local sessions|Local Sessions|localOnly|start_local_session|backend-created|backendCreated" AGENTS.md docs lib test scripts --glob '!logs/**'
```

Expected before edits: matches in docs, runtime, and tests.

Use these replacements:

- `local session metadata` -> `device-stored service-session metadata`
- `preserve local session and media` -> `preserve active service session and media`
- `silently ending the local session` -> `silently ending the active service session`
- `Access old sessions` -> `Review stored media and legacy capture folders`
- `backend-created session` -> `service-created session`
- `localOnly` -> remove the sentence or describe that legacy payloads are ignored and service session creation is always used
- `start_local_session` -> remove from current runbooks; if historical evidence must stay, mark it as historical and not current behavior

- [x] **Step 2: Add debug cleanup contract to merge plan**

In `docs/control/hydracam-mobo-media-timeline-merge-plan.md`, add a section:

```markdown
### Debug Session Cleanup Contract

Debug builds create service sessions whose `SessionId` starts with
`debug-<platform>-<utc timestamp>`. The mobile app records the service GUID,
display session id, and numeric MoBo id when the create response includes one.
Uploaded debug media is deleted from the device after successful upload even
when the normal release setting keeps local files.

The service cleanup lane is `POST /api/sessions/debug/delete?sessionGuid=<guid>&id=<numericId>`.
Until that endpoint is present in MoBo or media-timeline, mobile clients only
record cleanup candidates and cleanup scripts can be run against a staging
implementation with an explicit bearer token.
```

- [x] **Step 3: Run docs/static checks**

Run:

```bash
python3 scripts/test_no_local_sessions.py
git diff --check
```

Expected: PASS.

---

### Task 9: Full Validation

**Files:**
- No source edits in this task.

- [x] **Step 1: Run static no-leftovers checks**

Run:

```bash
rg -n "Local Sessions|View Local Sessions|Or\\.\\.\\.|localOnly|start_local_session|backend-created|backendCreated|preserving local session|local session preserved" lib test scripts docs AGENTS.md --glob '!logs/**'
python3 scripts/test_no_local_sessions.py
```

Expected: no `rg` matches outside historical evidence docs that explicitly say the behavior is historical, and Python test PASS.

- [x] **Step 2: Run Flutter analyzer**

Run:

```bash
flutter analyze
```

Expected: PASS with no new analyzer errors.

- [x] **Step 3: Run focused Flutter tests**

Run:

```bash
flutter test \
  test/models/session_upload_state_test.dart \
  test/services/session_manager_test.dart \
  test/services/uploader_service_test.dart \
  test/services/debug_session_policy_test.dart \
  test/services/debug_session_registry_test.dart \
  test/services/hydracam_api_service_test.dart \
  test/master/master_screen_test.dart \
  test/slave/slave_client_registration_test.dart \
  test/screens/previous_sessions_screen_test.dart \
  test/screens/session_details_screen_test.dart
```

Expected: PASS.

- [x] **Step 4: Run device-facing smoke if hardware is attached**

Run:

```bash
python3 scripts/run_hardware_ui_e2e.py --route standby --route setup
```

Expected: PASS on selected attached Android devices with screenshots under `logs/verification-runs/<run>/`. If no device is attached or unlocked, record the exact device blocker and skip only this gate.

Status: local validation recorded the current hardware boundary in
`logs/verification-runs/20260618-1314-session-upload-state-debug-cleanup/`;
ADB reported no attached Android devices, while Flutter saw wireless iPad and
iPhone but physical iOS launch was not rerun from this session. Same-day Android
setup-route UI smoke is available in
`logs/verification-runs/20260618-0953-session-concepts-android-ui/`.

- [ ] **Step 5: Verify debug session behavior on a debug build**

Run a debug automation capture with `start_session`, capture one photo, upload it, and inspect:

```bash
rg -n "debug-" logs/verification-runs/<run>
rg -n "Deleted uploaded local file" logs/verification-runs/<run>
```

Expected: the created service session id starts with `debug-`, uploaded media is deleted locally, and the debug cleanup registry contains the service GUID plus numeric id if the service returned one.

Status: unit/widget/API coverage proves the policy, metadata, registry,
cleanup client contract, and debug-session upload delete decision. A live
debug-build capture/upload smoke remains pending until a responsive device and
approved service endpoint/credentials are available.

---

## Self-Review

- Spec coverage: the plan removes the local-session concept from runtime, UI copy, tests, docs, and automation; replaces it with service sessions and computed upload state; labels debug build sessions; deletes debug media after upload; and prepares service-side debug-session deletion through a typed client contract plus cleanup script.
- Placeholder scan: the plan contains no blocked placeholder markers or unnamed generic test steps. Each code step includes concrete code or exact replacement text.
- Type consistency: `startCreatedSession`, `joinSession`, `DebugSessionPolicy`, `DebugSessionRegistry`, `DebugSessionRef`, `SessionUploadState`, and `summarizeSessionUpload` are introduced before later tasks call them.
