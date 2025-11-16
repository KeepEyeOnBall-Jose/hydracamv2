# HydraCam Recovery Plan — 2025-11-16

## 1. Current State Snapshot

| Area | Status | Evidence / Notes |
| --- | --- | --- |
| Android builds | Untested today; last verified Nov 15. | `TESTING_SUMMARY.md` claims green builds, but we still need a fresh `flutter build apk --debug` plus smoke test once unit tests pass. |
| Desktop (macOS/Windows/Linux) | Not recently exercised. | Builds reportedly succeeded on Nov 15, yet no recent binaries or field tests exist. |
| iOS | Blocked. | `pod install` fails even after `pod deintegrate`/`gem install`; team agreed to pause iOS until Android + desktop recover. |
| Automated tests | Failing. | `flutter test` currently surfaces 5 failures (SessionManager fixtures + StorageService timer). |
| Missing features | Battery, gallery persistence, critical storage enforcement regressed. | Plugins were removed during AGP migration; functionality now stubbed or commented. |
| Documentation | Slightly outdated. | README + TESTING_SUMMARY reference green builds/tests, so they need an update once fixes land. |

## 2. Feature Inventory & Expectations

| Feature | Expected Behaviour | Current Status | Restoration Plan |
| --- | --- | --- | --- |
| Master/slave discovery & WebSocket control | Master advertises itself over UDP, slaves auto-discover and open WS channel for commands. | Code intact (`master_master_announcer`, `slave/master_discovery.dart`), but only verified in emulator previously. No recent real-device validation. | Schedule multi-phone test once anchors in place; add integration test harness that simulates UDP + WS events. |
| Camera capture (photo/video) | Master and slaves can take photos/videos with flash toggles, respecting camera quality settings. | Works in manual testing but automated coverage flaky. Gallery persistence disabled after removing `gallery_saver`. | Keep `camera` package pinned for now. Implement saving via `photo_manager` (new helper to create HydraCam album) and cover with service tests. |
| Session management & uploader | Sessions created per match, media queued via `UploaderService`, metadata stored locally then uploaded. | Logic present but `SessionManager` tests fail due to file IO expectations (`CapturedPhoto`/`CapturedVideo` require real paths). | Introduce fake file helpers or temp files in tests; ensure uploader queue flush tested with anchors. |
| Battery monitoring | Warn user and optionally block recording when battery < threshold. | Entire service commented out because `battery_info` plugin incompatible with new AGP. | Adopt `battery_plus` (or `device_info_plus` battery channel) for Android-only baseline; stubbed behaviour for desktop. Add low-battery notifier test. |
| Storage monitoring | Warn at <1.5 GB free, block recording <0.5 GB, force-stop video. | `StorageService` polls via `disk_space_plus`, UI snackbar works, but `onCriticalStorageCallback` no longer stops recording (callback commented). Also leaves timer pending in widget tests. | Re-enable callback to `CameraServiceSingleton` with dependency injection to make it testable; ensure timers are canceled/overridden in tests. |
| Gallery saving (auto) | Every captured photo/video also lands in system "HydraCam" album. | TODO markers in `CameraService`: `GallerySaver.save*` calls removed; no replacement yet. Manual add-from-gallery still works (`AddGalleryMediaButton`). | Implement new `GalleryPersistenceService` using `photo_manager` write APIs (Android scoped storage & iOS Photos). Cover with unit tests using mocks. |
| Connectivity & hotspot awareness | Show toasts/logging if master/slave loses Wi-Fi or hotspot. | `connectivity_plus` and `network_info_plus` dependencies exist; need to confirm UI wiring still active after refactors. | Add anchoring test for `MasterScreen` connectivity banner; consider using `connectivity_plus_platform_interface` mocks. |
| Location tagging | Capture GPS for sessions (used by courts/sports center screens). | `LocationService` initialises in `main.dart`, but there are no runtime permission fallbacks nor tests. | Add location mock + service unit test to ensure coordinates stored, and provide manual override in settings. |
| Auth0 login + API sync | User logs in, selects court, uploads media via MoBo API. | Flows exist but need regression tests because dependencies (`flutter_appauth`) recently bumped. | Create API mock adapter and flow test (login → session → upload). |
| Logging/Diagnostics | `LogService` centralises logs, should expose to UI (log screen). | Works but logs show binding errors during tests. | Add anchor verifying `LogService` gracefully handles background isolates. |

## 3. Anchoring Tests To Add

1. **Storage enforcement test** (unit + widget): inject fake `DiskSpacePlus` values to ensure `StorageService` blocks recording and cancels timers when disposed.
2. **Session file IO tests**: use `io.Patch` or `setUp` temp directories so `CapturedPhoto/Video` can compute sizes without crashing; verify `SessionManager.addPhoto/addVideo` updates the session list.
3. **Gallery persistence test**: once `photo_manager` write helper exists, mock `PhotoManager.editor.save*` to assert the service is invoked with HydraCam album name.
4. **Battery warning test**: after migrating to `battery_plus`, simulate low battery stream and assert snackbar creation + throttling logic.
5. **Master-slave command flow test**: integration test (possibly using `test/fakes/master_slave_flow_test.dart`) that spins up master WebSocket server, connects fake slaves, and asserts commands propagate with the right payload.
6. **Uploader retry test**: mock HTTP client to throw transient errors and assert exponential backoff / queue state.
7. **Desktop bootstrap test**: verify app boots with no camera present (desktop mode) and surfaces a "camera unavailable" log instead of crashing.
8. **Widget smoke test fix**: wrap `HydraCamApp` with `FakeAsync().flushTimers()` or inject mock `StorageService` so no pending timers remain.

Each anchoring test should live close to the affected feature (e.g., `test/services/storage_service_test.dart`), and CI must run them on every branch before manual device tests begin.

## 4. Package & Plugin Strategy

1. **Audit**: `flutter pub outdated --mode=null-safety` to list pending upgrades without bumping blindly.
2. **Critical restorations**:
   - Add `battery_plus: ^5.x` (supports Android/iOS/desktop) and refactor `BatteryService` to subscribe via stream API.
   - Implement gallery writes via `photo_manager` (requires `PhotoManager.editor.saveImage/Video`). Consider adding `permission_handler` prompts for Photos on iOS (future) even if iOS paused.
   - Confirm `disk_space_plus` works across Android API 34; if not, swap for `device_space_plus` or native channel fallback.
3. **Gradual upgrades**: once anchors green, upgrade networking/auth packages (`http`, `flutter_appauth`, `connectivity_plus`) to the latest stable. Run analyzer/tests after each bump.
4. **Automate**: add a GitHub Action (or local script) for `flutter analyze`, `flutter test`, optional `melos` style `flutter pub run dart_code_metrics:metrics`. Document run steps in `TESTING_SUMMARY.md`.

## 5. Multiplatform Manual Test Matrix

| Scenario | Devices | What to Verify |
| --- | --- | --- |
| Android master + 2 Android slaves | Pixel 6 (master), Moto G / Samsung A (slaves) | Discovery, command propagation, session persistence, auto gallery save, uploader queue. |
| Android master + Windows laptop (viewer) | Android master hotspot, Windows app acts as slave/client | Desktop UI handles lack of camera gracefully yet still logs sessions. |
| Android master + macOS desktop | Android master + macOS monitoring build | Storage/battery overlays degrade gracefully despite missing sensors. |
| Offline / hotspot lost | Drop slave Wi-Fi mid-recording | Reconnection, log messaging, and upload resume behaviour. |
| Low battery + low storage | Android device with emulated low batt/storage (adb) | Warnings trigger, recording blocked, logs captured. |

Document each run in `TESTING_SUMMARY.md` (date, devices, pass/fail, bugs). Keep at least one Android-only regression pass before every release candidate.

## 6. Execution Roadmap

1. **Stabilize CI**
   - Fix failing `SessionManager` tests by using temp files or loosening constructors.
   - Mock/disable `StorageService` timers in widget tests; ensure no pending timers.
2. **Restore missing features**
   - Re-implement battery monitoring via `battery_plus`.
   - Add `GalleryPersistenceService` and wire into `CameraService.takePhoto/stopRecordingVideo`.
   - Re-enable critical storage enforcement hook in `CameraServiceSingleton`.
3. **Anchor behaviours**
   - Implement test list in §3.
   - Update `TESTING_SUMMARY.md` with new expectations and commands.
4. **Upgrade packages safely**
   - Run `flutter pub outdated`; bump camera + networking packages as long as tests stay green.
   - Capture migration notes (Android manifest permissions, Gradle tweaks) in `MIGRATION_NOTES.md`.
5. **Manual multi-device shakedown**
   - Run matrix from §5, record findings, open bugs for discrepancies.
   - Once Android/desktop solid, reassess iOS viability (or keep paused explicitly in docs).

## 7. Open Questions / Dependencies

- Do we need macOS/Windows camera support, or are desktops monitoring-only? Clarify to scope testing.
- Are MoBo API endpoints stable? Need their staging credentials for integration tests.
- Should we continue investing in iOS right now, or freeze pods to avoid drift?

Keeping this plan up to date: append dated sections as we execute, and link issues/PRs that implement each task.
