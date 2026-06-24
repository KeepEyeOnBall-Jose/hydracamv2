# Hybrid Build & Deploy Plan

> Created: 2026-06-24

Durable plan for building and deploying HydraCam across a fleet of devices that
is split between two Macs: some devices attached to the local Mac, others to a
remote Mac reached over SSH/Tailscale.

## Topology

- **This Mac** (`jose-mbp`) owns its USB/wireless-adb devices.
- **Remote Mac** (`joss-macbook-air`, MBA 13 M1) owns the devices attached to
  it; reachable over Tailscale SSH (see `scripts/adb_remote_bridge.sh`).
- The repo is checked out on both Macs at the same path.

Current fleet (2026-06-24):

| Device | Serial | Host | Notes |
| --- | --- | --- | --- |
| S10e (glasses/watch governor) | `RF8M21J8XRT` | this Mac | also wireless-adb Watch4 |
| Galaxy Watch4 | `192.168.178.117:41145` | this Mac | Wear OS module |
| iPhone (26.5) | `00008101-…` | this Mac | iOS, `xcrun devicectl` |
| iPad 5 (17.7) | `8b406aa5…` | this Mac | iOS |
| S7 edge | `9885e6503930304946` | M1 | Android |
| S10e #2 | `RF8M90QE7LX` | M1 | Android |

## Core principle: build once, control per-host

The phones synchronize **peer-to-peer over Wi-Fi** — slaves connect to the
master *phone's* LAN IP over the master/slave WebSocket. The Macs only build,
deploy, and control over adb. Therefore:

- **All phones must be on one Wi-Fi LAN** for synchronized capture.
- The Macs do **not** need to be on that LAN (Tailscale is enough for control).
- Role (master/slave) and the master phone IP are chosen **at launch**, not at
  build, via `am start` intent extras — so one APK serves every Android device.

## Deployment modes

1. **Local-only** — devices on this Mac. Plain `adb`.
2. **Remote-only** — devices on the M1. `ssh <host> adb …`; the APK is copied
   to the remote once.
3. **Hybrid (both)** — build once here, install to local devices with `adb` and
   to remote devices via `ssh <host> adb` (APK scp'd to the remote). Slaves on
   either Mac point at the same master phone IP.
4. **Build on both** — for fastest iteration when each Mac drives its own
   devices, run `flutter build apk` on each Mac from the synced branch.

## One-command tool: `scripts/hybrid_deploy.sh`

Driven by a fleet file (`scripts/clock-sync/fleet.example.conf` → `fleet.conf`):

```bash
scripts/hybrid_deploy.sh build                 # automation APK
scripts/hybrid_deploy.sh deploy                 # build + distribute + install + launch all
scripts/hybrid_deploy.sh deploy --skip-build    # reuse existing APK
scripts/hybrid_deploy.sh launch                 # re-launch roles only
scripts/hybrid_deploy.sh list                   # parsed fleet + adb reachability
```

The fleet file declares `MASTER_IP` (master phone's Wi-Fi IP) and one
`name serial host role` line per device, where `host` is `local` or an SSH
target. The script installs the automation-enabled APK
(`--dart-define=HYDRACAM_AUTOMATION=true`), grants camera/audio/storage
permissions, launches each device into its role, and forwards the master's
automation bridge (`:4762`) for headless control. Slaves are launched first so
the master finds them on start.

## iOS path

iPhone/iPad are not adb devices. Build and deploy with the existing iOS lane:

```bash
flutter build ios --profile --dart-define=HYDRACAM_AUTOMATION=true -t lib/main.dart
xcrun devicectl device install app --device <uuid> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <uuid> --terminate-existing \
  --environment-variables '{"HYDRACAM_AUTOMATION_ROLE":"slave","HYDRACAM_AUTOMATION_MASTER_IP":"<master-ip>","HYDRACAM_AUTOMATION_FORCE_SLAVE":"true"}' \
  com.keepeyeonball
```

iOS role is passed via process environment variables (read in
`ios/Runner/AppDelegate.swift`), mirroring the Android intent extras. iOS
devices join the same Wi-Fi LAN and the same master phone IP.

## Cross-Mac adb for interactive work

For driving a single remote device interactively from this Mac (e.g. the Watch4
clock work), `scripts/adb_remote_bridge.sh` tunnels the remote adb server over
Tailscale and points local `adb` at it. `hybrid_deploy.sh` instead uses
`ssh <host> adb` per device, which needs no tunnel and handles many devices
cleanly.

## Gotchas

- The automation bridge (`:4762`) has no auth — keep it on a trusted LAN /
  tailnet only.
- `preferredMasterIp` is the master **phone's** IP, not a Mac's.
- Granting a permission that a given Android version lacks is harmless
  (ignored); the script tolerates it.
- Remote bridge control needs an SSH local-forward to the remote `:4762`
  (the deploy/capture scripts print or open the tunnel).
