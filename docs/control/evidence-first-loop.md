# HydraCam Evidence-First Advancement Loop

This is the required verification loop for recurring HydraCam project work.
It consumes only existing control-plane work from `docs/control/` and requires
run-specific evidence before an item can be called complete.

## Source Order

Pick one existing item, in this order:

1. `docs/control/status-and-roadmap.md` release blockers.
2. `docs/control/backlog-import.md` priority issue candidates.
3. `docs/control/architecture-and-testing.md` mobile test priorities.
4. `docs/control/requirements.md` mobile or cross-project FR/NFR rows.

Do not create a new task during the loop. Allowed outcomes are: completed,
partially completed, blocked with evidence, verified already complete, or
deferred with a reason on the existing item.

## Evidence Pack Contract

Every iteration must create:

`logs/verification-runs/YYYYMMDD-HHMM-<existing-item-slug>/`

Required contents:

- `summary.md`: selected item, change made, acceptance checks, device matrix,
  exact commands, pass/fail, blockers, and evidence paths.
- `commands.log`: command transcript or copied command output.
- `git-status-before.txt` and `git-status-after.txt`.
- `screenshots/`: screenshots of the relevant running instance state.
- `video/`: screen recordings for user-visible or multi-step workflows.
- `device-logs/`: Android, iOS simulator, or physical-device logs.
- `artifacts.json`: structured device, tier, scenario, evidence, and acceptance
  metadata.

Use `scripts/evidence_pack.py` to create, record commands for, finalize, and
validate the pack.

## Verification Ladder

Use the strongest available tier for the selected item:

| Tier | Required for | Minimum evidence |
| --- | --- | --- |
| A: real hardware | Physical camera/gallery, battery/storage, local networking, release/profile launch, and release blockers | Device model/OS, launch or flow video, screenshots, device logs. |
| B: emulator/simulator e2e | UI, session, upload queue, navigation, settings, non-camera app behavior | Emulator/simulator screenshot, video for flows, device logs. |
| C: multi-device emulated cluster | master/slave, reconnect, network identity, sync, auto-record, upload orchestration | Master plus slave screenshots/video, orchestrator output, device logs. |
| D: integration/unit tests | pure service/model logic only | Focused tests and analyzer. Hardware evidence is optional only when no running app behavior changes. |

Generic analyzer or unit-test output is not enough for UI, device, session,
network, recording, or release-blocker work.

## Standard Cycle

1. Run `git status -sb` and create the evidence pack before editing.
2. Write acceptance checks in the pack before implementation.
3. Capture baseline behavior when practical.
4. Implement one small slice from the selected existing item.
5. Capture improvement-specific screenshots, video, logs, and command output.
6. Run code gates:
   - Dart/Flutter: `flutter analyze --no-pub`.
   - Focused tests: `flutter test --no-pub <relevant targets>`.
   - Docs-only: targeted `git diff --check -- <touched files>`.
7. Finalize and validate the evidence pack.
8. Update only the existing `docs/control` item with evidence path and
   disposition.
9. End with `git status -sb`.

## Helper Usage

Create a run:

```bash
python3 scripts/evidence_pack.py start \
  --item "Validate iOS release/profile physical-device launch and capture" \
  --slug ios-release-profile-smoke \
  --source "docs/control/status-and-roadmap.md#release-blockers" \
  --tier A \
  --acceptance "Physical iPhone or iPad reaches the expected first app screen" \
  --acceptance "Photo and video capture work or produce actionable logs"
```

Record commands into the pack:

```bash
python3 scripts/evidence_pack.py run logs/verification-runs/<run> -- \
  flutter analyze --no-pub
```

Declare the device under test:

```bash
python3 scripts/evidence_pack.py add-device logs/verification-runs/<run> \
  --name "iPhone 16 Plus" \
  --kind "iOS simulator" \
  --identifier "<device-udid>" \
  --role "single app instance" \
  --os "iOS 18.4"
```

Capture hardware evidence with platform tools:

```bash
# Android screenshot/video/logs
adb -s <serial> exec-out screencap -p > logs/verification-runs/<run>/screenshots/<serial>.png
adb -s <serial> shell screenrecord /sdcard/hydracam-evidence.mp4
adb -s <serial> pull /sdcard/hydracam-evidence.mp4 logs/verification-runs/<run>/video/<serial>.mp4
adb -s <serial> logcat -d > logs/verification-runs/<run>/device-logs/<serial>-logcat.txt

# iOS simulator screenshot/video/logs
xcrun simctl io <device-udid> screenshot logs/verification-runs/<run>/screenshots/<device>.png
xcrun simctl io <device-udid> recordVideo logs/verification-runs/<run>/video/<device>.mp4
xcrun simctl spawn <device-udid> log show --style compact --last 5m > logs/verification-runs/<run>/device-logs/<device>-logs.txt
```

Finalize and validate:

```bash
python3 scripts/evidence_pack.py finalize logs/verification-runs/<run> \
  --status passed \
  --note "Evidence shows the selected acceptance checks."

python3 scripts/evidence_pack.py check logs/verification-runs/<run>
```

## Evidence Storage Policy (2026-08-26)

Raw device artifacts (logcat `.txt` dumps `>= 200 KB`, screenshots, screen
recordings, media files) are no longer committed to git. Evidence packs under
`logs/verification-runs/` keep `summary.md`, `commands.log`, and small
structured logs (for example `artifacts.json`). Raw artifacts stay on the
capture host or external storage and are referenced by path/hash from
`summary.md`.

## Default Priority Queue

1. Release/profile real-device smoke readiness.
2. Session and media data-loss risks.
3. Two-device master/slave capture readiness.
4. Upload and capture reliability.
5. Battery, storage, and network safety.
6. Existing-flow regression coverage.
7. Lower-priority UX and future platform work.
