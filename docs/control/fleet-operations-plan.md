# HydraCam Fleet Operations Plan

This document defines the first above-HydraCam operating layer for phones that
stay deployed, powered, remotely supervised, and ready to record. The initial
decision is **lab-managed Android fleet**, not full MDM, for the first
production-shaped prototype.

HydraCam remains the edge capture app. The fleet layer owns enrollment,
inventory, remote health, remote commands, network readiness, support access,
and long-running evidence.

## Scope Decision

Use a lab-managed Android setup first:

- Target phone class: Samsung Galaxy S10e / `SM-G970F` on Android 12, with
  Android API 24+ as the repo support floor.
- Device management: physical labels, USB-authorized ADB, wireless ADB only on
  trusted lab networks, disabled battery optimization for HydraCam, and
  `Stay awake` while charging.
- Deployment: install current HydraCam build through the existing Flutter/ADB
  lanes, then keep the device on a stable lab Wi-Fi or HydraCam hotspot with
  client isolation disabled.
- Remote access: normal operations must use fleet commands and health payloads.
  ADB/scrcpy/VPN access is break-glass support only, temporary, and limited to
  trusted networks.

Do not treat lab-managed ADB as the final production remote-access model. The
next production step is Android Enterprise/MDM or a dedicated kiosk/device
management service for enrollment, app updates, kiosk mode, remote lock/wipe,
and audited remote support.

## Required Layers Above HydraCam

1. Physical inventory and power
   - Durable label, model, serial, assigned venue/court/angle, charger, mount,
     cable, spare-device pool, and battery replacement status.
   - Powered state is a fleet health gate. A deployed always-on phone that is
     not on AC/USB/wireless power is failed, not merely degraded.

2. Venue network
   - Stable router/hotspot, no client isolation, known SSID, reachable local
     subnet, and enough upload bandwidth for queued video.
   - DHCP reservations or recorded IP history are preferred for support, but
     identity must come from device ID plus heartbeat payload, not IP alone.

3. Fleet heartbeat and command plane
   - Every deployed phone should periodically report identity, app build,
     runtime role, recording state, active session, upload queue, network,
     battery, storage, warnings, blockers, and supported commands.
   - Normal remote actions should be product-level commands: report status,
     set role, start/stop session, take photo, start/stop recording, capture a
     diagnostic screenshot, upload logs, and restart the app.

4. Operator dashboard
   - Show venue/court/device readiness, last heartbeat age, network health,
     powered state, battery, thermal/storage risk, recording state, upload
     queue, app version drift, and last command result.

5. Media and processing pipeline
   - Preserve resumable uploads, backend session/material linkage, processing
     queue status, replay/retry, retention, and audit proof that a clip belongs
     to the right event/court/device/session.

6. Security and compliance
   - HTTPS outside local LAN flows, per-device identity, credential rotation,
     command audit logs, no DB credentials on mobile, no persisted venue Wi-Fi
     secrets in repo artifacts, and GDPR/consent gates before recording where
     product requires them.

## Implemented In This Repo

The first repo implementation is intentionally local and contract-shaped:

- App-side fleet heartbeat snapshot and collector:
  `lib/services/fleet_heartbeat_service.dart`.
- Heartbeat test coverage:
  `test/services/fleet_heartbeat_service_test.dart`.
- Android always-on lab soak harness:
  `scripts/run_android_always_on_lab_soak.py`.
- Soak harness test coverage:
  `scripts/test_run_android_always_on_lab_soak.py`.

The backend receiver, dashboard, command persistence, and remote command
execution transport are not implemented in this mobile repo yet. They should be
built above HydraCam using the contract below. The `supportedCommands` field is
the declared product-command contract for that future receiver; it is not proof
that a deployed command channel can execute those commands today.

## Fleet Heartbeat Contract

Schema version: `1`.

Current app-side builder: `FleetHeartbeatCollector.collect()`.

Required top-level fields:

```json
{
  "schemaVersion": 1,
  "generatedAtUtc": "2026-06-15T10:30:00.000Z",
  "deviceId": "device-abc123",
  "labLabel": "HydraCam-S10e-01",
  "fleetMode": "lab-managed",
  "health": "ready",
  "app": {
    "version": "1.4.0",
    "buildNumber": "16",
    "packageName": "com.amaia23.hydracam"
  },
  "device": {
    "brand": "samsung",
    "model": "SM-G970F",
    "version.release": "12"
  },
  "role": {
    "current": "slave",
    "recording": false,
    "activeSessionGuid": "session-123"
  },
  "network": {
    "isWifiActive": true,
    "ipAddress": "192.168.178.42",
    "ssid": "HydraCamLab",
    "gatewayIp": "192.168.178.1",
    "subnetSignature": "192.168.178.0/24",
    "localControlReady": true,
    "readinessMessage": "Local network ready."
  },
  "battery": {
    "levelPercent": 87,
    "state": "charging"
  },
  "storage": {
    "freeGb": 37.5
  },
  "upload": {
    "queueDepth": 2
  },
  "warnings": [],
  "blockers": [],
  "supportedCommands": [
    "report_status",
    "set_role",
    "start_session",
    "stop_session",
    "take_photo",
    "start_recording",
    "stop_recording",
    "capture_diagnostic_screenshot",
    "upload_logs",
    "restart_app"
  ]
}
```

Health calculation:

- `ready`: no warnings and no blockers.
- `warning`: warnings present, no blockers.
- `blocked`: one or more blockers present.

Current blocker codes:

- `network:wifi-disabled`
- `network:no-local-ip`
- `battery:critical`
- `storage:critical`

Current warning codes:

- `network:ssid-unavailable`
- `network:unavailable`
- `app:package-info-unavailable`
- `battery:unknown`
- `battery:low`
- `storage:unknown`
- `storage:low`

Transport plan:

1. Mobile sends this payload on app launch, role changes, session changes,
   recording start/stop, upload queue changes, and a periodic interval.
2. First backend path can be HTTPS `POST /api/fleet/heartbeats`.
3. Later real-time command delivery can use Azure SignalR or another outbound
   device channel, but command responses should still be persisted as auditable
   events.
4. A device should never accept arbitrary shell commands from the fleet plane.
   Only declared product commands are valid.

## Always-On S10e Soak Plan

Purpose: prove that one lab-managed S10e can remain deployed, powered, app-ready,
and remotely inspectable before claiming unattended operation.

Minimum useful proof: 24 hours. Preferred proof before venue claims: 72 hours.

Run prerequisites:

1. Label the phone, for example `HydraCam-S10e-01`.
2. Join the stable lab Wi-Fi or HydraCam hotspot.
3. Disable client isolation on the router/hotspot.
4. Enable Developer options, USB debugging, and `Stay awake`.
5. Disable battery optimization for HydraCam.
6. Install and launch HydraCam.
7. Keep the phone on reliable power.
8. Optional but preferred: start the automation bridge and pass its `/healthz`
   URL to the soak harness. The harness validates that the bridge
   `automationTargetId` matches one of the selected ADB device serials, so a
   stale bridge URL cannot satisfy the run.

Short smoke:

```bash
python3 scripts/run_android_always_on_lab_soak.py \
  --device RF8M90QE7LX \
  --duration-seconds 120 \
  --interval-seconds 30 \
  --bridge-healthz-url http://192.168.178.42:4762/healthz
```

24-hour proof:

```bash
python3 scripts/run_android_always_on_lab_soak.py \
  --device RF8M90QE7LX \
  --duration-hours 24 \
  --interval-seconds 60 \
  --bridge-healthz-url http://192.168.178.42:4762/healthz \
  --run-dir logs/verification-runs/$(date +%Y%m%d-%H%M)-s10e-always-on-24h
```

The harness writes:

- `metadata.json`
- `raw-samples.jsonl`
- `power-summary.json`
- `bridge-healthz.json`
- `always-on-summary.json`

The run fails when:

- No Android device is sampled.
- The selected device does not match expected model `SM-G970F`.
- The HydraCam app process is missing, unless
  `--allow-missing-app-process` is explicitly supplied.
- The device is not on AC/USB/wireless power.
- Battery is critical.
- Temperature reaches 45 C or higher.
- The bridge `/healthz` probe fails.
- The run records fewer samples than the duration/interval requires.

Warnings do not fail the run, but they must be reviewed before claiming a venue
is unattended-ready.

## Next Backend Work

1. Implement `POST /api/fleet/heartbeats` and store payloads keyed by
   `deviceId`, `labLabel`, venue, and court.
2. Add dashboard views for stale heartbeats, blocked devices, app-version drift,
   active recording, and upload queue depth.
3. Define command persistence: requested command, target device, accepted time,
   executed time, result, error, and operator.
4. Add a mobile command receiver only after the command auth and audit model are
   explicit.
