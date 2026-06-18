# Local IDE, Emulator, And Deploy Playbook

Use this playbook to run HydraCam manually from the local Mac while following
the repository development process in `AGENTS.md`,
`docs/control/evidence-first-loop.md`, and
`docs/control/regular-evaluation-plan.md`.

## Recommended IDEs

Use all three tools, each for the part it owns best:

| Tool | Use it for | Do not rely on it for |
| --- | --- | --- |
| VS Code | Daily Dart/Flutter editing, analyzer/test tasks, quick launch on the currently selected Flutter device. | App Store signing, Android SDK package management, or final release uploads. |
| Android Studio | Android SDK/AVD Manager, emulator images, Android manifests, Gradle inspection, physical Android debug prompts. | iOS signing or TestFlight. |
| Xcode | iOS simulator/device management, Developer Mode/trust, signing, provisioning, App Store archive inspection. | Android emulators or Play Console deploys. |

The command line remains the source of truth. IDEs should run the same scripts
documented here instead of replacing them.

## One-Time Local Setup

1. Open the repo:

```bash
cd /Users/jose/src/work/hydracamv2
git status -sb
```

2. Confirm the installed toolchain:

```bash
flutter doctor -v
flutter emulators
flutter devices --device-timeout 10
adb devices -l
xcrun devicectl list devices
```

3. In VS Code, install the recommended workspace extensions when prompted:
   Dart, Flutter, Python, and YAML.

4. In Android Studio, open this folder as the project:

```bash
open -a "Android Studio" .
```

Use Device Manager to inspect or edit AVDs. Current useful AVD names include
`Pixel_7`, `Medium_Phone_API_36`, and the Hydra cluster AVDs
`Hydra_Master_API34`, `Hydra_SlaveA_API34`, `Hydra_SlaveB_API34`, and
`Hydra_SlaveC_API34`.

5. In Xcode, open the generated iOS workspace, not the raw project:

```bash
open ios/Runner.xcworkspace
```

Use Window > Devices and Simulators for physical iPhone/iPad pairing,
Developer Mode, network debugging, and provisioning state.

## Daily Development Loop

Start with current repo and device truth:

```bash
git status -sb
flutter devices --device-timeout 10
adb devices -l
xcrun devicectl list devices
```

For code changes, run:

```bash
flutter analyze --no-pub
flutter test --no-pub <focused-test-file-or-directory>
git diff --check
```

Before handoff or commit, run the full suite unless the change is docs-only or
the suite is blocked:

```bash
flutter test --no-pub
```

For user-facing, device-facing, release, camera, upload, storage, network, or
master/slave work, start an evidence pack before claiming the behavior:

```bash
python3 scripts/evidence_pack.py start \
  --item "<existing control-plane item>" \
  --slug "<short-run-slug>" \
  --source "docs/control/regular-evaluation-plan.md" \
  --tier B \
  --acceptance "<observable acceptance check>" \
  --require-screenshots \
  --require-device-logs
```

Use Tier A for physical hardware, Tier B for one simulator/emulator, Tier C for
multi-device role switching, and Tier D for tests-only logic.

## Run From VS Code

Use Run and Debug for these checked-in launch configurations:

- `HydraCam (pick current device)`: lets the Flutter extension pick a visible
  target.
- `HydraCam (Android emulator-5554)`: after booting one Android emulator.
- `HydraCam (iPhone 16 Plus simulator)`: current booted iOS simulator.
- `HydraCam (connected iPad)`: current physical iPad Flutter device id.
- `HydraCam (macOS desktop)` and `HydraCam (Chrome web)`: desktop/web smoke
  paths.
- `HydraCam automation (Android emulator-5554)`: launches with
  `HYDRACAM_AUTOMATION=true` for automation-route checks.
- `HydraCam profile/release (pick current device)`: use only when the target is
  already trusted and the lane needs profile/release behavior.

Use Terminal > Run Task for common commands:

- `flutter: Doctor`
- `flutter: Analyze`
- `flutter: Test Full`
- `flutter: Test Focused`
- `devices: Flutter Devices`
- `devices: Android ADB Devices`
- `devices: iOS CoreDevice List`
- `emulator: List Flutter Emulators`
- `emulator: Boot Pixel_7`
- `emulator: Boot Hydra Cluster`
- `emulator: Stop All`
- `evidence: Start Pack`
- `evidence: Check Pack`
- `release: Store Readiness Local`
- `release: Build Android Store AAB`
- `release: Build iOS Store IPA`
- `deploy: Android Google Play Internal`
- `deploy: iOS TestFlight Beta`

## Run Emulators Manually

List what Flutter can see:

```bash
flutter emulators
```

Boot one Android emulator for normal UI work:

```bash
python3 scripts/boot_and_verify_emulators.py \
  --count 1 \
  --avd-base Pixel_7 \
  --start \
  --timeout 180
```

Boot the four-AVD Hydra cluster for multi-device emulator work:

```bash
python3 scripts/boot_and_verify_emulators.py \
  --hydra-cluster \
  --start \
  --timeout 180
```

Run the app on the first Android emulator:

```bash
flutter run -d emulator-5554
```

Stop Android and iOS simulators when finished:

```bash
python3 scripts/stop_and_verify_all_emulators.py
```

Boot or inspect iOS simulators with Xcode or:

```bash
xcrun simctl list devices available
open -a Simulator
flutter run -d <ios-simulator-udid>
```

Simulator/emulator output proves launch, navigation, layout, settings, and
non-camera behavior. It does not prove real camera/gallery/local-network or
release behavior.

## Run Physical Devices Manually

Android:

```bash
adb devices -l
python3 scripts/android_wifi_preflight.py \
  --expected-subnet 192.168.178.0/24 \
  --device <adb-serial> \
  --check-only
flutter run -d <adb-serial>
```

iPhone/iPad:

```bash
xcrun devicectl list devices
flutter devices --device-timeout 10
flutter run -d <flutter-ios-device-id>
```

If iOS debug attach hangs but the app can run, use the CoreDevice launch path
documented in `docs/control/wireless-device-debugging.md` and capture device
logs before treating it as an app bug.

## Deploy And Release Lanes

First run the local store-readiness preflight:

```bash
scripts/check_store_readiness.sh local
```

Build store artifacts without uploading:

```bash
scripts/build_store_artifacts.sh android
scripts/build_store_artifacts.sh ios
```

Fastlane wrappers use the repo-pinned Bundler environment:

```bash
scripts/android_fastlane.sh build_store
scripts/ios_fastlane.sh build_store
```

Upload lanes require credentials and should only be run when the account state
is intentional:

```bash
GOOGLE_PLAY_JSON_KEY=/path/to/play-service-account.json \
  scripts/android_fastlane.sh internal

APP_STORE_CONNECT_API_KEY_PATH=/path/to/app-store-connect-key.json \
  TESTFLIGHT_CHANGELOG="<short changelog>" \
  scripts/ios_fastlane.sh beta
```

Current release blockers should be treated as real blockers, not app passes:
missing iOS distribution signing identity, missing App Store Connect key,
missing Google Play JSON key, or missing public HTTPS privacy/support/account
deletion URLs.

## Remote Mac Host Deploy

For a new Mac build host, use the existing wrapper:

```bash
scripts/deploy_macos_dev_host.zsh --dry-run jose@new-mac.tail6ce139.ts.net
scripts/deploy_macos_dev_host.zsh jose@new-mac.tail6ce139.ts.net
```

Use `--password-file tempass.txt` only when the ignored local password file is
intentionally available. See `docs/control/macos-dev-host.md` for the full
contract and validation levels.

## Finish A Run

Finish with:

```bash
git diff --check
git status -sb
```

For evidence-backed work:

```bash
python3 scripts/evidence_pack.py finalize logs/verification-runs/<run> \
  --status <passed|failed|blocked|partial> \
  --note "<short factual result>"
python3 scripts/evidence_pack.py check logs/verification-runs/<run>
```

Then update the existing control-plane item with the evidence path if the repo
truth changed.
