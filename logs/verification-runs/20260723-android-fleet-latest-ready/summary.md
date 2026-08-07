# Android Fleet Latest-Build Readiness

- Date: 2026-07-23
- Source checkout: `master-jose-2025` at `fe03d200ce57`
- App version: `1.4.0+19`
- Android artifact: `build/app/outputs/flutter-apk/app-debug.apk`
- Android artifact SHA-256:
  `d3ec46dd4c4e46685fa9dd4a8607a824a6255f263c6524d076ebdca7e57e52ce`
- Build define: `HYDRACAM_AUTOMATION=true`

## Validation

- `flutter analyze`: passed with no issues.
- Android build: passed after selecting Android Studio JBR 21 and disabling
  Gradle native integration for this invocation. The prior configured
  Homebrew JDK blocked in `java --version`.
- Install: all six ADB-visible Android devices report `versionName=1.4.0` and
  `versionCode=19`.
- Launch: all six devices retained a live `com.amaia23.hydracam` process.
- Recent-log check: no HydraCam fatal exception or ANR on any selected Android
  device.

## Device Matrix

| Operator role | Serial | Install | Launch/readiness | Network |
| --- | --- | --- | --- | --- |
| S9 old | `29d816ac550b7ece` | `1.4.0+19` | Visible HydraCam Master Control screenshot; ready | `192.168.178.153` |
| S7 edge | `9885e6503930304946` | `1.4.0+19` | Process alive; secure keyguard blocks foreground proof | `192.168.178.64` |
| S10e Przemek I | `RF8M2125DAJ` | `1.4.0+19` | Visible HydraCam Slave screen; ready after LAN join | Wi-Fi enabled, no association |
| S10e main | `RF8M21J8XRT` | `1.4.0+19` | Process alive; display/keyguard needs operator unlock | `192.168.178.175` |
| S10e Przemek II | `RF8M40MT6AW` | `1.4.0+19` | Visible HydraCam Slave screen; ready after LAN join | Wi-Fi enabled, no association |
| S10e broken-screen | `RF8M90QE7LX` | `1.4.0+19` | Process alive; display/keyguard needs operator unlock | `192.168.178.160` |

Przemek I and Przemek II have saved Astral Express and JuJo profiles, but
neither SSID is currently in scan range. The current FRITZ network is visible
but not saved on those two phones, so a one-time manual join or securely
supplied credential is required.

## Apple Targets

- iPhone 12 Pro was CoreDevice-available and paired at the start of the run.
  The signed Profile `Runner.app` is valid and declares `1.4.0+19`. A fresh
  install/launch could not be completed because macOS AppleSystemPolicy began
  returning `Too many open files` for all assessments and killed `devicectl`.
  The M1's own `devicectl` remained healthy and saw the phone as available, but
  the app-bundle transfer timed out and the M1 then became SSH-unreachable.
  The existing project evidence records this physical iPhone running
  `1.4.0+19`, but that installed version could not be re-read in this run.
- iPhone 11 was paired but CoreDevice-unavailable. It needs an unlock and
  Developer Mode before install/launch.

## Inventory Reconciliation

`docs/control/hybrid-deploy-plan.md` was reconciled with the media-timeline
camera-device manifest. S7, S9 old, and S10e Przemek I have manifest-confirmed
serials. The remaining S10e operator labels are explicitly marked as inferred.
S9 new remains absent from both live USB/ADB and the media-timeline manifest.

## Result

Partial readiness. All six connected Android phones have the latest build and
run without an observed crash. Operator unlock/LAN actions remain for the
specific devices above. Apple deployment is blocked by the current Mac host
policy failure plus the M1 dropping off SSH; wake/reconnect or reboot the Macs
before retrying `devicectl`.
