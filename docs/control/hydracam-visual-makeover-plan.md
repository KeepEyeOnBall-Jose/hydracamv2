# HydraCam Visual Makeover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make HydraCam feel like the mobile capture companion to MediaTimeline by adopting the squash club visual system, preserving capture reliability, and giving both platforms a shared operational language.

**Architecture:** Keep HydraCam as a focused Flutter mobile capture app and MediaTimeline as the review, processing, and analytics surface. Share design principles, color roles, typography direction, component semantics, and status language, but translate layout patterns to mobile constraints instead of copying web sidebar/table layouts into the app.

**Tech Stack:** Flutter, Dart, Material widgets, existing `lib/app_theme.dart`, existing HydraCam screens and widgets, MediaTimeline squash design tokens from `/Users/jose/src/work/media-timeline/frontend/src/index.css`, `/Users/jose/src/work/media-timeline/frontend/tailwind.config.js`, and `/Users/jose/src/work/media-timeline/docs/design-system/SQUASH_DESIGN_SYSTEM.md`.

---

Last reviewed: 2026-06-12.

Implementation status: implemented on branch `codex/hydracam-visual-makeover`.
The 2026-06-18 evidence pack
`logs/verification-runs/20260618-1346-hydracam-visual-system-core-surfaces/`
passed focused visual/theme tests, `flutter analyze --no-pub`, full
`flutter test --no-pub`, and `adb devices -l`. Same-turn Android hardware UI
smoke was not run because ADB reported no attached devices; keep hardware
screenshot/log proof open until a responsive Android target is visible.

## Source Evidence

- HydraCam theme entrypoint: `lib/app_theme.dart` currently uses a light scaffold, Roboto text styles, yellow primary `#FFC107`, yellow-orange accent `#FFA000`, and ad hoc black/gray text roles.
- HydraCam app shell: `lib/widgets/hydra_cam_app_bar.dart` uses the central theme but still has a blue login icon and a menu-heavy top bar.
- HydraCam primary surfaces: `lib/screens/role_selection_screen.dart`, `lib/master/master_screen.dart`, `lib/slave/slave_screen.dart`, `lib/screens/camera_setup_preview_screen.dart`, and `lib/automation/automation_standby_screen.dart` are operational mobile screens, not marketing screens.
- MediaTimeline design system: `docs/design-system/SQUASH_DESIGN_SYSTEM.md` defines the strict squash club palette, semantic tokens, page rules, primitives, typography, icon rule, and verification guards.
- MediaTimeline token layer: `frontend/src/index.css`, `frontend/tailwind.config.js`, and `frontend/src/design/palette.ts` define semantic roles over black, white, yellow `#FFC107`, red `#D32F2F`, and neutral grays.
- MediaTimeline primitives: `frontend/src/components/ui/primitives.tsx` defines PageShell, Surface, Toolbar, Button, Badge, and StatusPill patterns.
- MediaTimeline reference UI: `frontend/src/pages/reference/HydraCamExplorer.tsx`, `frontend/src/components/Layout.tsx`, and `frontend/src/components/Sidebar.tsx` show the current operational look: dense, calm, token-driven, icon-supported, and status-forward.

## Visual Thesis

HydraCam should feel like a court-side capture terminal that feeds MediaTimeline: black camera canvas, light operational surfaces, yellow for active intent, red only for blockers, and restrained controls that stay readable under pressure.

## Content Plan

HydraCam is an app surface, not a landing page. The first screen should immediately support work.

1. Role and session orientation: device role, session state, local network readiness, and the next safe action.
2. Setup and capture workspace: live preview, leveling, camera perspective, role status, recording state, and primary capture actions.
3. Device and upload status: connected clients, battery/storage/network signals, queue state, and media count.
4. Secondary administration: settings, login, logs, support/store links, app version, and diagnostics.

## Interaction Thesis

1. Role and session transitions should feel immediate and mechanical: short cross-fades or slide transitions only where they clarify mode changes.
2. Recording, upload, and connected-client states should use explicit text plus icons and minimal motion; pulse only for live capture or active sync.
3. Toolbars and selection controls should behave like MediaTimeline primitives: clear selected state, icon plus label for commands, no ornamental animation.

## Platform Homogeneity Contract

Homogeneity means shared semantics, not identical layouts.

| Design role | MediaTimeline source | HydraCam translation |
| --- | --- | --- |
| Brand palette | Black, white, yellow `#FFC107`, red `#D32F2F`, semantic neutral grays | Add Flutter semantic tokens and remove ad hoc blue/orange accents from app chrome |
| Page shell | Dark navigation frame with light page content | Dark app chrome and camera canvases; light operational panels where text density matters |
| Surface | `Surface`, `Toolbar`, `Button`, `Badge`, `StatusPill` primitives | `HydraCamSurface`, `HydraCamToolbar`, themed buttons, status chips, and badges |
| Typography | Montserrat, bold headings, compact body scale | Prefer Montserrat only after bundled font assets or a dependency decision; otherwise use system sans with matching weights and scale |
| Icons | Material Icons | Keep Material Icons and use them consistently for role, camera, sync, upload, settings, diagnostics, and warnings |
| Status semantics | Status text is explicit; hue is secondary | Every status chip names the state and uses icon/text; red is reserved for error, destructive, disconnected, or critical resource states |
| Analytics and review | Tables, timelines, CV overlays, detail pages | Do not copy review UI into mobile; mobile shows capture readiness and upload handoff only |

## Principles

1. Capture first. The camera preview, recording state, and safe capture action are always visually dominant on capture screens.
2. Shared palette, semantic roles. HydraCam should use the same black, white, yellow, red, and neutral gray roles as MediaTimeline, with colors centralized in `lib/app_theme.dart` or a small theme submodule.
3. Red is exceptional. Use red for destructive, error, disconnected, permission-blocked, battery/storage-critical, or failed-upload states only.
4. Yellow means active intent. Use yellow for primary action, selected role, active recording readiness, current master, current route, and interactive focus.
5. Dark canvas, light work panels. Camera and dimmed/standby surfaces can be dark. Forms, settings, tables/lists, and diagnostics should use light surfaces for readability.
6. Operational density beats decoration. Avoid hero sections, ornamental gradients, card mosaics, and marketing copy. Use compact panels, toolbars, badges, and lists.
7. Status must be readable without color. Every status indicator needs text and, where useful, a Material icon.
8. One visual language across capture and review. Terminology should match MediaTimeline where it overlaps: session, event, device, media, upload, processing, local status, bridge, and timeline handoff.
9. Mobile constraints override web shape. MediaTimeline sidebars and tables become top app bar actions, bottom/action bars, compact sections, or scrollable lists on phones.
10. Evidence before rollout. UI implementation must pass Flutter tests and, for device-facing screens, the hardware UI evidence path required by `AGENTS.md`.

## Current Gaps

- `AppTheme` is centralized but too shallow: it exposes a few colors instead of semantic roles for page, surface, text, border, accent, danger, warning, and inverse text.
- The current accent set uses yellow-orange `#FFA000`, which weakens homogeneity with MediaTimeline's strict yellow and red contract.
- The app shell has at least one non-system blue icon in `HydraCamAppBar`, which violates the target palette.
- Capture/setup screens rely on default Material layout and do not yet expose MediaTimeline-like primitives for surfaces, toolbars, badges, or status pills.
- Role selection is functionally direct, but it does not yet establish the capture-terminal identity or show readiness context.
- Automation standby and camera setup already have constrained layouts; they are good first targets for a low-risk visual migration.

## File Responsibilities For Implementation

- `lib/app_theme.dart`: owns Flutter color roles, text theme, Material component themes, and legacy compatibility getters during migration.
- `lib/widgets/hydracam_surface.dart`: reusable light/dark surface, toolbar, badge, and status chip widgets that mirror MediaTimeline primitives in Flutter.
- `lib/screens/role_selection_screen.dart`: first operational surface; role choice, readiness summary, and session orientation.
- `lib/screens/camera_setup_preview_screen.dart`: capture setup surface; preview canvas, level overlay, perspective selector, and primary recording action.
- `lib/automation/automation_standby_screen.dart`: compact dark/light standby surface for automation mode.
- `lib/widgets/hydra_cam_app_bar.dart`: app chrome, menu icons, palette compliance, and compact action behavior.
- `lib/master/master_screen.dart` and `lib/slave/slave_screen.dart`: staged adoption for capture status, media list, session info, and upload controls after primitives land.
- `test/theme/hydracam_theme_test.dart`: token and component-theme assertions.
- `test/theme/no_ad_hoc_color_test.dart`: source guard for obvious palette violations in `lib/`.
- Existing widget tests near changed screens: update rather than replace.

## Implementation Tasks

### Task 1: Establish The Flutter Squash Theme Contract

**Files:**
- Modify: `lib/app_theme.dart`
- Create: `test/theme/hydracam_theme_test.dart`
- Create: `test/theme/no_ad_hoc_color_test.dart`

- [x] Add token assertions for exact squash palette values:

```dart
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/app_theme.dart";

void main() {
  test("squash palette matches MediaTimeline contract", () {
    expect(AppTheme.squashBlack, const Color(0xFF000000));
    expect(AppTheme.squashWhite, const Color(0xFFFFFFFF));
    expect(AppTheme.squashYellow, const Color(0xFFFFC107));
    expect(AppTheme.squashRed, const Color(0xFFD32F2F));
  });
}
```

- [x] Add a palette guard that scans `lib/` for literal non-contract colors used in UI code. Initial allowlist should include existing camera black/white preview constants and migration compatibility aliases; every allowlisted value needs a named reason in the test.
- [x] Run `flutter test test/theme/hydracam_theme_test.dart test/theme/no_ad_hoc_color_test.dart` against the current theme implementation.
- [x] Replace `AppTheme` with semantic roles: `pageBackground`, `surface`, `surfaceMuted`, `textPrimary`, `textSecondary`, `border`, `accent`, `danger`, `critical`, `inverseText`, and compatibility aliases for existing callers.
- [x] Update `ThemeData` for app bars, buttons, switches, inputs, dialogs, snackbars, cards, dividers, and text styles. Keep border radius at 8 or below unless an existing widget requires otherwise.
- [x] Run `flutter format lib/app_theme.dart test/theme/hydracam_theme_test.dart test/theme/no_ad_hoc_color_test.dart`.
- [x] Run `flutter test test/theme/hydracam_theme_test.dart test/theme/no_ad_hoc_color_test.dart`.
- [x] Run `flutter analyze`.

### Task 2: Add MediaTimeline-Like Flutter Primitives

**Files:**
- Create: `lib/widgets/hydracam_surface.dart`
- Create: `test/widgets/hydracam_surface_test.dart`

- [x] Write widget tests for `HydraCamSurface`, `HydraCamToolbar`, `HydraCamBadge`, and `HydraCamStatusChip`. Tests should assert explicit text labels are present, danger styling is only selected by an explicit `danger` tone, and disabled controls keep readable text.
- [x] Run `flutter test test/widgets/hydracam_surface_test.dart` against the current primitive implementation.
- [x] Implement the primitives with Material widgets and `AppTheme` roles:
  - `HydraCamSurface`: light default, muted variant, dark canvas variant, danger variant.
  - `HydraCamToolbar`: compact wrap layout with stable spacing.
  - `HydraCamBadge`: icon plus label optional, no color-only state.
  - `HydraCamStatusChip`: enum-backed status values for neutral, active, warning, danger, and recording.
- [x] Run `flutter format lib/widgets/hydracam_surface.dart test/widgets/hydracam_surface_test.dart`.
- [x] Run `flutter test test/widgets/hydracam_surface_test.dart`.
- [x] Run `flutter analyze`.

### Task 3: Make Role Selection The Operational Entry Surface

**Files:**
- Modify: `lib/screens/role_selection_screen.dart`
- Create: `test/screens/role_selection_screen_test.dart`

- [x] Write or update a widget test that proves the screen shows `Master`, `Slave`, current session/readiness copy, and two large accessible role actions without overflow at phone width.
- [x] Run the focused role-selection widget test. Expected before implementation: either fails due missing readiness copy or confirms the baseline constraints that should be preserved.
- [x] Replace the centered spacer layout with a compact operational surface: app title, readiness/status strip, two role action rows, and secondary diagnostics entry only if it is already available through the app shell.
- [x] Use the new primitives from Task 2 and remove direct ad hoc colors.
- [x] Run `flutter test` for the focused role-selection test.
- [x] Run `flutter analyze`.

### Task 4: Migrate Low-Risk Setup And Standby Screens First

**Files:**
- Modify: `lib/screens/camera_setup_preview_screen.dart`
- Modify: `lib/automation/automation_standby_screen.dart`
- Modify: `test/widgets/camera_setup_preview_screen_test.dart`
- Modify: `test/automation/automation_standby_screen_test.dart`

- [x] Update tests to assert the setup route keeps the preview framed, perspective selector visible, start action visible when provided, and no overflow on compact heights.
- [x] Update tests to assert automation standby uses explicit waiting text, one primary action when `onOpenNormalApp` exists, and no overflow on short screens.
- [x] Run the focused tests. Expected before implementation: preserve current behavior and expose any missing target styling semantics.
- [x] Apply the squash theme primitives: black preview canvas, light control panel, yellow primary action, neutral border, and explicit status chip.
- [x] Run `flutter test test/widgets/camera_setup_preview_screen_test.dart test/automation/automation_standby_screen_test.dart`.
- [x] Run `flutter analyze`.
- [x] If Android hardware is connected and responsive, run:

```bash
python3 scripts/run_hardware_ui_e2e.py --route setup --route standby --output-dir logs/verification-runs/20260612-visual-makeover-setup-standby
```

Expected: screenshots and logs under the run directory, no Flutter overflow markers.

Current validation note: not run in this pass because `adb devices -l` returned
no attached devices and `flutter devices --device-timeout 10` hung until
interrupted.

### Task 5: Refresh The Shared App Chrome

**Files:**
- Modify: `lib/widgets/hydra_cam_app_bar.dart`
- Modify: `test/widgets/hydra_cam_app_bar_test.dart`

- [x] Write or update tests that cover compact width behavior, popup menu labels, icons, and palette-compliant login/account icon styling.
- [x] Run `flutter test test/widgets/hydra_cam_app_bar_test.dart`. Expected before implementation: a new palette assertion should fail because the login icon currently uses blue.
- [x] Rework the app bar with the theme contract: dark or yellow-accent chrome according to the selected global theme, no blue icon, stable compact behavior, menu icon labels preserved.
- [x] Run `flutter test test/widgets/hydra_cam_app_bar_test.dart`.
- [x] Run `flutter analyze`.

### Task 6: Bring Master And Slave Capture Screens Into The Same System

**Files:**
- Modify: `lib/master/master_screen.dart`
- Modify: `lib/slave/slave_screen.dart`
- Modify: existing master/slave widget tests or create focused tests around status/control builders

- [x] Identify the smallest testable builders for session state, sync status, media list, and capture controls before editing layout.
- [x] Add tests that prove active session, no session, recording, dimmed standby, upload, and connected-client states remain explicit in text and icons.
- [x] Run the focused tests. Expected before implementation: functional baseline passes, new style/status requirements fail if not yet represented.
- [x] Replace only local visual structure with primitives. Keep capture, WebSocket, session, upload, and dimming logic untouched.
- [x] Run the focused tests, then run the relevant broader Flutter tests for master/slave state.
- [x] Run `flutter analyze`.
- [x] For device-facing changes, run the same-turn hardware UI smoke required by `AGENTS.md` on attached responsive hardware, selecting the affected routes.

Current validation note: not run in this pass because `adb devices -l` returned
no attached devices.

### Task 7: Align Secondary Screens Without Expanding Scope

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/screens/login_screen.dart`
- Modify: `lib/screens/courts_screen.dart`
- Modify: `lib/screens/sports_centers_screen.dart`
- Modify: `lib/screens/sessions_screen.dart`
- Modify: focused existing tests for those screens

- [x] Update tests for visible labels, buttons, links, and no-overflow behavior before styling edits.
- [x] Apply the same surface, toolbar, button, badge, and typography rules.
- [x] Keep privacy/support/account-deletion text functionally unchanged; this work is visual alignment only.
- [x] Run focused tests for touched screens.
- [x] Run `flutter analyze`.

### Task 8: Add A Visual Compliance Gate

**Files:**
- Modify: `test/theme/no_ad_hoc_color_test.dart`
- Modify: `docs/control/hydracam-visual-makeover-plan.md`
- Optionally modify: `AGENTS.md` only if the team wants the guard to become a permanent repo rule

- [x] Expand the source guard after migration to fail on new literal UI colors outside `AppTheme`, `CameraLevelOverlay`, camera-preview black/white, and platform-required constants.
- [x] Document any permanent exceptions in the test file, not in comments scattered through UI code.
- [x] Run `flutter test test/theme/no_ad_hoc_color_test.dart`.
- [x] Run `flutter analyze`.
- [x] If `AGENTS.md` is updated, run `git diff --check`.

## Rollout Order

1. Theme contract and primitives.
2. Setup preview and automation standby.
3. App bar and role selection.
4. Master/slave capture screens.
5. Secondary settings/login/court/session screens.
6. Visual compliance guard tightened after migration.

This order reduces risk because it proves the shared visual language on small, already-tested surfaces before touching capture-heavy master/slave flows.

## Validation Gates

- Docs-only changes: `git diff --check`.
- Theme/primitives: `flutter test test/theme/hydracam_theme_test.dart test/theme/no_ad_hoc_color_test.dart test/widgets/hydracam_surface_test.dart` and `flutter analyze`.
- Screen changes: focused widget tests for the changed screens, then `flutter analyze`.
- Capture-facing screens: focused tests plus the most relevant hardware UI smoke with `scripts/run_hardware_ui_e2e.py`.
- Shared session, WebSocket, upload, or app startup changes: full `flutter test` plus `flutter analyze`.

## Explicit Non-Goals

- Do not move HydraCam mobile into MediaTimeline.
- Do not copy MediaTimeline tables, sidebar density, or analytics views into the mobile app.
- Do not change capture/session/WebSocket/upload behavior as part of styling tasks.
- Do not add marketing hero pages or onboarding copy before the operational role/capture flow.
- Do not introduce new color families for success/info states; use text, icons, opacity, border style, and existing palette roles.

## Open Decisions

1. Font path: either bundle Montserrat with license-compatible assets or use the platform sans stack with MediaTimeline-like weights.
2. Dark shell extent: decide whether HydraCam's global scaffold becomes dark by default or whether only app chrome/camera surfaces become dark while page content stays light.
3. Brand mark: decide whether the current launcher icon should become a visible in-app mark on the role screen and standby screen.
4. Device screenshot baseline: choose one Android and one iOS viewport as the visual regression baseline before broad capture-screen migration.

## Definition Of Done

- HydraCam has centralized semantic theme roles matching the squash palette.
- New UI code uses primitives or `AppTheme` roles instead of literal UI colors.
- Role selection, camera setup, automation standby, app chrome, and master/slave capture screens visually read as one product family.
- MediaTimeline and HydraCam share status language and color semantics for session, device, media, upload, and bridge states.
- Focused tests, `flutter analyze`, and required hardware UI evidence pass for changed device-facing routes.
