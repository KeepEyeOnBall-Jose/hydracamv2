# HydraCam UI Flow Layout Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove current UI drift in the master controls, make court selection center-first and explicit, fit the slave screen on S10e-class landscape viewports, and make clock-sync status age-aware instead of frozen at calibration time.

**Architecture:** Keep the existing Flutter visual makeover primitives and make focused local changes. Master command sizing stays in `MasterScreen`; court selection gets a typed nullable selection model; slave compactness is an opt-in landscape phone mode; time sync gains reusable freshness helpers consumed by UI and client connection boundaries.

**Tech Stack:** Flutter/Dart, widget tests with `flutter_test`, existing HydraCam services and evidence-pack scripts.

---

### Task 1: Master Action Consistency

**Files:**
- Modify: `lib/master/master_screen.dart`
- Test: `test/master/master_screen_test.dart`

- [x] Add button geometry assertions to the compact master screen test for `Size(360, 640)` and `Size(640, 360)`.
- [x] Give every master action slot the same explicit height and width contract, including the gallery import slot.
- [x] Keep existing callbacks, busy states, icon labels, and danger styling intact.
- [x] Run: `flutter test --no-pub test/master/master_screen_test.dart`

### Task 2: Court Selection Flow

**Files:**
- Modify: `lib/widgets/court_selection_widget.dart`
- Modify: `lib/master/master_screen.dart`
- Test: `test/widgets/court_selection_widget_test.dart`
- Test: `test/master/master_screen_test.dart`

- [x] Replace the hidden expansion/dropdown flow with an always-visible center-first selector.
- [x] Add a typed `CourtSelection` model and make the callback nullable so parent state clears when the center or clear action changes selection.
- [x] Use court GUID as the actual selected value so duplicate court names remain safe.
- [x] Show a persistent selected-court summary with clear/change affordance.
- [x] Preserve automation/debug ability to start without a court, but make user taps confirm the no-court path before creating a session.
- [x] Run: `flutter test --no-pub test/widgets/court_selection_widget_test.dart test/master/master_screen_test.dart`

### Task 3: Slave S10e Landscape Layout

**Files:**
- Modify: `lib/slave/slave_screen.dart`
- Test: `test/slave/slave_screen_fast_connect_test.dart`
- Test: `test/slave/slave_screen_sync_chip_test.dart`

- [x] Detect S10e-class compact landscape phone viewports without affecting tablet/desktop landscape.
- [x] Use compact diagnostics, reduced status-panel padding, shorter sync text, and tighter spacing only in that mode.
- [x] Keep camera preview bounded inside the existing `Expanded` region and avoid global app-bar or shared widget changes.
- [x] Add S10e-class `Size(760, 360)` tests for idle/connected, recording controls, and a long sync label.
- [x] Run: `flutter test --no-pub test/slave/slave_screen_fast_connect_test.dart test/slave/slave_screen_sync_chip_test.dart`

### Task 4: Clock Sync Freshness

**Files:**
- Modify: `lib/constants.dart`
- Modify: `lib/services/time_sync_service.dart`
- Modify: `lib/slave/slave_client.dart`
- Modify: `lib/slave/slave_screen.dart`
- Test: `test/services/time_sync_service_test.dart`
- Test: `test/slave/slave_client_time_sync_test.dart`
- Test: `test/slave/slave_screen_sync_chip_test.dart`

- [x] Add age-aware confidence helpers and a max-stale threshold.
- [x] Recompute slave UI status over time and show calibration age.
- [x] Reset calibration/clock offset on disconnect and before a fresh master connection.
- [x] Allow scheduled-command master-time fallback when the latest calibration is stale, not only when it is absent.
- [x] Keep steady-state probe volume bounded; do not add broad master traffic.
- [x] Run: `flutter test --no-pub test/services/time_sync_service_test.dart test/slave/slave_client_time_sync_test.dart test/slave/slave_screen_sync_chip_test.dart`

### Task 5: Validation And Reintegrate

**Files:**
- Modify: `logs/verification-runs/20260622-1855-ui-flow-layout-sync-drift/summary.md`
- Modify: `docs/control/status-and-roadmap.md` if the evidence path needs a durable note.

- [x] Run focused tests for every touched area.
- [x] Run `flutter analyze --no-pub`.
- [x] Record final commands and device/S10e blocker state in the evidence pack.
- [x] Finalize and check the evidence pack.

## Completion Audit

- [x] Code and focused tests cover the master screen, court selection, S10e-class widget layout, and clock-sync fallback/refresh behavior.
- [x] Android emulator proof captured the actual slave screen in landscape at `866 x 388` with no Flutter overflow markers:
  `logs/verification-runs/20260622-1934-ui-flow-layout-sync-emulator-slave-screen-landscape-after-trim/`.
- [ ] Physical S10e proof remains outstanding because no ADB-visible S10e was connected during the continuation audit.
