# Android Manual Launch Escape

- Date: 2026-06-09
- Status: passed
- APK: `build/app/outputs/flutter-apk/app-debug.apk`
- Build: `flutter build apk --debug --no-pub --dart-define=HYDRACAM_AUTOMATION=true --dart-define=HYDRACAM_AUTOMATION_PORT=4762`

## Devices

| Serial | Model | Result |
| --- | --- | --- |
| `29d816ac550b7ece` | SM-G960F | Reinstalled, standby launch showed `Open HydraCam`, launcher reopen returned to manual HydraCam |
| `RF8M21J8XRT` | SM-G970F | Reinstalled, standby launch showed `Open HydraCam`, launcher reopen returned to manual HydraCam |
| `RF8M90QE7LX` | SM-G970F | Reinstalled, standby launch showed `Open HydraCam`, launcher reopen returned to manual HydraCam |

## Verification

- Targeted tests:
  - `flutter test test/automation/runtime_role_switch_test.dart`
  - `flutter test test/automation/automation_standby_screen_test.dart`
- Static analysis: `flutter analyze`
- Device flow:
  1. Force-stopped each target.
  2. Launched each target with `--es role standby --es automationTargetId <serial>`.
  3. Confirmed the standby UI exposed `Automation standby`, `Waiting for role assignment`, and `Open HydraCam`.
  4. Sent each device Home.
  5. Started each target with normal launcher intent and no automation extras.
  6. Confirmed the UI changed to manual HydraCam (`HydraCam - Master Control`) and no longer exposed `Automation standby`.

## Evidence Files

- `screenshots/android-29d816ac550b7ece-manual-after-launcher.png`
- `screenshots/android-RF8M21J8XRT-manual-after-launcher.png`
- `screenshots/android-RF8M90QE7LX-manual-after-launcher.png`
- `xml/android-29d816ac550b7ece-manual-after-launcher.xml`
- `xml/android-RF8M21J8XRT-manual-after-launcher.xml`
- `xml/android-RF8M90QE7LX-manual-after-launcher.xml`
