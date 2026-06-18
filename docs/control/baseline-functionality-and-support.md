# Baseline Functionality And Support

Last refreshed: 2026-06-15.

This document is the basic ground for HydraCam support claims. It condenses
current evidence into the minimum functionality baseline, the hardware/emulator
matrix, and the checks required before claiming a target is supported.

Use `docs/control/status-and-roadmap.md` for detailed dated history and
`docs/control/regular-evaluation-plan.md` for the run commands. This file is the
short contract: installed, visible, or theoretically compatible is not enough.
A target counts only for the scope that has current evidence.

## Baseline Terms

| Term | Meaning |
| --- | --- |
| Baseline-supported | The app has a dated proof pack for the named scope, and a fresh run should be attempted before handoff or release claims. |
| Conditional | The target has useful proof but also a current blocker, stale bridge, missing metadata, or lane-specific caveat. Count it only after rerunning the named gate. |
| Validation-only | Useful for launch, navigation, layout, settings, or automation plumbing. Do not use it for camera, gallery, physical local-network, or release/profile claims. |
| Blocked | The target is present or historically used but cannot be counted until the blocker is resolved and the proof is rerun. |
| Unsupported | Out of scope unless a product decision explicitly reopens it. |

## Functionality Baseline

| Capability | Minimum claim | Current baseline |
| --- | --- | --- |
| App launch and core UI | HydraCam builds, installs, launches, reaches setup/standby or equivalent route, captures screenshot/log evidence, and has no Flutter overflow markers. | Android hardware setup/standby passed on S7 edge and two S10e devices in `logs/verification-runs/20260611-s7-two-s10e-hardware-ui-oriented-scroll-e2e/summary.md`. iOS simulator platform smoke passed in `logs/verification-runs/20260612-0657-regular-evaluation-tier-b-simulator-baseline/summary.md`. |
| Single-device camera capture | Physical camera target saves one photo and one video at the claimed lens/profile, with artifacts or native trace evidence. | Android S10e/G960F have `autoBack` + `standard1080p30` evidence in the June 7 matrices. S7 edge has direct 1920x1080 photo/video proof in `logs/verification-runs/20260609-1405-s7-higher-resolution-compat/summary.md`. iPhone 12 Pro capture passed after the gallery timeout fix in `logs/verification-runs/20260612-1723-cleanup-attached-phone-validation/summary.md`. |
| Session and upload | A created session receives media, upload is attempted through the supported contract, and local/session state is inspectable. | iPhone capture created a backend session and saved local media in the June 12 attached-phone run. Legacy upload through the HydraCam contract into session `489` and media-timeline import/readiness passed in `logs/verification-runs/20260614-0941-hydracam-multicamera-legacy-mediatimeline-flow/summary.md`; that proof uses a small test set, not live phone capture. |
| Master/slave role switching | Every selected target is declared by id, all selected targets are on the same reachable LAN, each selected target can become master, and the master sees expected clients. | Six-device current-build iOS/Android role switching passed in `logs/verification-runs/20260609-0930-all-hardware-ios-android-update-role-test/summary.md`. A later eight-target attempt was blocked by ADB command timeouts and split subnets in `logs/verification-runs/20260611-0237-eight-target-random-master-role-switch/summary.md`; do not claim eight-target support. |
| Multi-device capture synchronization | Role-switch proof plus actual photo/video artifacts from the selected master/slave capture flow in the same run. | Not yet baseline-supported. The June 7 parallel matrix proves independent local capture under a shared barrier, not master/slave broadcast capture. The next production baseline needs same-LAN discovery, slave connection, photo, video start/stop, local save, upload queue, and session end in one selected-set run. |
| Store/release readiness | Exact release/profile lane builds, installs, launches, and passes real-device smoke for the store bundle. | Android signed AAB readiness is locally proven in status docs. iOS store upload remains dependent on App Store Connect upload credentials and release-lane smoke; do not claim production readiness from debug/profile automation alone. |

## Supported Hardware

| Target | Status | Supported scope | Caveats and proof |
| --- | --- | --- | --- |
| Android API 24+ real phones | Baseline-supported floor | Primary Android validation and distribution floor. Use physical hardware for camera, gallery, local network, battery, storage, and release claims. | Current app minSdk is 24. Re-inventory every run with `adb devices -l` and `flutter devices --device-timeout 10`. |
| Samsung SM-G960F / Android 10 API 29 / `29d816ac550b7ece` | Baseline-supported | UI smoke, `standard1080p30` capture, and role-switch participation. | Visible in the 2026-06-15 local ADB/Flutter inventory. June 7 evidence supersedes an earlier camera failure. |
| Samsung S10e SM-G970F / Android 12 API 31 / `RF8M21J8XRT`, `RF8M90QE7LX` | Baseline-supported when visible | UI smoke, `standard1080p30` capture, and role-switch participation. | Both S10e devices passed the June 11 hardware UI route smoke and earlier capture/role evidence. If a unit is not currently ADB-visible, record it as unavailable rather than dropping it silently from an all-device claim. |
| Samsung S7 edge SM-G935F / Android 8 API 26 / `9885e6503930304946` | Conditional low-end supported | UI smoke and direct `standard1080p30` photo/video save through the SM-G935F compatibility path. | Visible in the 2026-06-15 local ADB/Flutter inventory. Keep the backend/session automation timeout separate from camera support. 1080p60 and 4K are unproven on this target. |
| iPhone 12 Pro / iOS 26.5 / `00008101-000A68811E43001E` | Conditional baseline-supported | Physical iOS capture, Profile bridge, and role switching. | `xcdevice` reported the phone available on 2026-06-15. Saved-video metadata is still unavailable in iOS matrices. For no-tooling launch, use the Profile automation path; debug `Runner.app` requires Flutter tooling. |
| Physical iPad / `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | Conditional | Prior iPad capture and role-switch proof; useful iOS tablet regression target. | `xcdevice` reported it unavailable on 2026-06-15, and the latest Tier A iPad baseline was blocked on automation bridge discovery. Count it only after `/healthz` or the capture repro proves the current bridge. |
| Xiaomi 2201116PG / Android 13 API 33 / `575ecf2cbd24` | Blocked | None for current baseline claims. | Repeatedly blocked by device-side `INSTALL_FAILED_USER_RESTRICTED`. The OS is new enough, but install policy prevents current app proof. |
| Lenovo Phab2 / Android 6.0.1 API 23 / `9d94c365` | Unsupported | None. | Current app minSdk is 24. Do not spend baseline or release-blocker time here unless product explicitly reopens legacy support. |
| macOS desktop | Validation-only | Controller/mock-camera development, automation bridge checks, and role-switch peer experiments. | Not a mobile camera support claim. macOS passed the visual-smoke bridge/screenshot lane in June 2026. |
| Windows, Linux, web, Chrome | Validation-only or experimental | Future platform exploration only. | Win11 native webcam/upload was partial and the triple-platform role matrix was aborted. Chrome/web is visible locally but not a supported HydraCam capture target. |

## Emulator And Simulator Support

| Target | Status | Supported scope | Caveats and proof |
| --- | --- | --- | --- |
| iOS Simulator, currently proven with iPhone 16 Plus / iOS 18.4 / `5CF4A12E-A8B5-4285-AE86-407B9067CB5F` | Validation-only, passing | Launch, integration platform smoke, navigation/layout, screenshots, and simulator logs. | Passed Tier B baseline in `logs/verification-runs/20260612-0657-regular-evaluation-tier-b-simulator-baseline/summary.md`. Do not use for camera/gallery proof because Flutter reports no simulator cameras. |
| Installed iOS simulator catalog | Validation-only | Pick a current iPhone/iPad simulator for UI smoke after booting it. | `xcrun simctl list devices booted` showed no booted iOS simulator on 2026-06-15. `xcdevice --timeout 10` listed available iPhone/iPad simulators for iOS 18.4 and 26.5. Apple Watch, Apple TV, and Vision simulators are out of HydraCam baseline scope. |
| Android `Pixel_7` AVD | Validation-only | Preferred single Android emulator for UI/navigation and automation route rehearsal after a clean rerun. | Installed locally. Must pass `scripts/run_hardware_ui_e2e.py --include-emulators` before being counted as a current passing emulator baseline. |
| Android `Medium_Phone_API_36` AVD | Blocked for current passing baseline | UI experiments only until rerun cleanly. | Latest visual smoke installed/launched but `/healthz` reported no automation commands; do not count it as a passing emulator baseline until fixed and rerun. |
| Android Hydra cluster AVDs `Hydra_Master_API34`, `Hydra_SlaveA_API34`, `Hydra_SlaveB_API34`, `Hydra_SlaveC_API34` | Validation-only | Multi-instance route/automation rehearsal. | Installed locally. They cannot prove physical camera, gallery, or same-LAN behavior for real phones. The June 11 eight-target attempt showed emulator-master role switching is not a substitute for LAN-routable physical-client proof. |
| Android `SaberWatch4` AVD | Unsupported | None. | Installed locally but not a HydraCam phone/tablet target. |

## Minimum Baseline Gates

Run these before claiming a new baseline or changing the support matrix:

1. Static truth:

```bash
git status -sb
flutter devices --device-timeout 10
adb devices -l
xcrun xcdevice list --timeout 10
flutter emulators
```

2. Repository checks for code changes:

```bash
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

3. Emulator/simulator UI lane:

```bash
flutter test integration_test/platform_test.dart -d <ios-simulator-udid>
python3 scripts/run_hardware_ui_e2e.py \
  --include-emulators \
  --device emulator-5554 \
  --route setup \
  --route standby \
  --run-dir logs/verification-runs/<run>
```

4. Physical hardware lane:

```bash
python3 scripts/run_hardware_ui_e2e.py \
  --device <adb-serial> \
  --route setup \
  --route standby \
  --run-dir logs/verification-runs/<run>

python3 scripts/ios_capture_repro.py \
  --launch \
  --device-id <ios-device-id> \
  --host auto \
  --run-dir logs/verification-runs/<run>
```

5. Multi-device lane:

```bash
python3 scripts/android_wifi_preflight.py \
  --expected-subnet auto \
  --expected-host <reachable-host> \
  --device <adb-serial> \
  --check-only

python3 scripts/run_rotating_master_slave_matrix.py \
  --prime-then-immediate-role-switch \
  --expect-target-id <device-id-1> \
  --expect-target-id <device-id-2> \
  --run-dir logs/verification-runs/<run>
```

Use repeated `--expect-target-id` flags for every device that must be part of
the claim. If a visible supported target is skipped, record the blocker or make
the narrowed scope explicit.

## Current Open Decisions

- Decide whether the S7 edge remains an official customer-supported low-end
  device or only a regression guardrail. Until changed, keep it as conditional
  low-end supported.
- Decide whether the physical iPad must be part of every iOS baseline or only a
  tablet regression lane. Until changed, count it only after bridge health is
  freshly proven.
- Fix or rerun the Android emulator UI lane before treating any Android AVD as a
  current passing baseline target.
- Produce one same-LAN, two-or-more-device capture proof that combines role
  switching, slave connection, photo, video start/stop, local save, upload
  queue, and session end.
