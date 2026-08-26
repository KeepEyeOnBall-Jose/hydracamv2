# HydraCam Automation Runbook

## 1. Prerequisites

- Flutter SDK + Android SDK/NDK with at least one API 34 system image.
- Python 3.9+ with standard library (script is dependency-free).
- `adb` on PATH and emulator images already created (e.g., `Hydra_Master_API34`, `Hydra_SlaveA_API34`).
- HydraCam APK built with automation flag: `flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true`.

## 1.1 Fastest way to reboot the last known-good automation flow

If you want to resume the previous emulator experiments from the safest default checkpoint, use the restart wrapper:

```sh
python3 scripts/reboot_automation_run.py \
  --boot-hydra-cluster \
  --cluster-size 3 \
  --manifest automation_scenarios/quad_smoke_extended.json \
  --scenario quad_smoke_extended
```

What it does:

1. Builds the Android automation APK unless `--skip-build` is passed.
2. Boots the standard Hydra emulator cluster when `--boot-hydra-cluster` is used.
3. Installs the APK, grants camera/audio/location/media permissions, and launches 1 master + N slaves.
4. Uses `preferredMasterIp=10.0.2.2` for emulator slaves and exposes the master's port `4040` via `adb forward`.
5. Runs `scripts/multi_device_orchestrator.py` with the chosen manifest.
6. Optionally shuts emulators back down with `--shutdown-emulators`.

Useful variations:

```sh
# Preview the whole plan without touching emulators or adb
python3 scripts/reboot_automation_run.py \
  --serials emulator-5554,emulator-5556,emulator-5558 \
  --dry-run

# Reuse already-running devices and skip the APK rebuild
python3 scripts/reboot_automation_run.py \
  --serials emulator-5554,emulator-5556,emulator-5558 \
  --skip-build \
  --scenario quad_smoke_extended
```

Important notes:

- Automation mode is enabled by the build-time dart define `HYDRACAM_AUTOMATION=true`; the launch intent only needs role-related extras.
- The Android package in this repo is `com.amaia23.hydracam`.
- The most recent successful artifact set in this workspace is `automation_runs/20251120_222427-quad_demo/`.

### Optional: Bootstrap four emulators from scratch

If `emulator -list-avds` does not show four ready AVDs, create them via the Android command-line tools (macOS paths shown; adjust for Linux/Windows):

```sh
SDK_ROOT=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}

# Install the Android 34 Play Store system image once
"$SDK_ROOT"/cmdline-tools/latest/bin/sdkmanager \
  --install "system-images;android-34;google_apis_playstore;arm64-v8a"

# Create 1 master + 3 slaves (re-run with different --name values as needed)
for name in Hydra_Master_API34 Hydra_SlaveA_API34 Hydra_SlaveB_API34 Hydra_SlaveC_API34; do
  yes | "$SDK_ROOT"/cmdline-tools/latest/bin/avdmanager create avd \
    --name "$name" \
    --device pixel_6 \
    --package "system-images;android-34;google_apis_playstore;arm64-v8a" \
    --sdcard 512M
done

# Launch each emulator on its own TCP port and shared emulator network IP
"$SDK_ROOT"/emulator/emulator -avd Hydra_Master_API34 -port 5554 -shared-net-id 11 -no-snapshot -gpu swiftshader_indirect &
"$SDK_ROOT"/emulator/emulator -avd Hydra_SlaveA_API34 -port 5556 -shared-net-id 12 -no-snapshot -gpu swiftshader_indirect &
"$SDK_ROOT"/emulator/emulator -avd Hydra_SlaveB_API34 -port 5558 -shared-net-id 13 -no-snapshot -gpu swiftshader_indirect &
"$SDK_ROOT"/emulator/emulator -avd Hydra_SlaveC_API34 -port 5560 -shared-net-id 14 -no-snapshot -gpu swiftshader_indirect &

# Pre-grant runtime permissions so automation isn't blocked by dialogs
for serial in emulator-5554 emulator-5556 emulator-5558 emulator-5560; do
  for perm in \
    android.permission.CAMERA \
    android.permission.RECORD_AUDIO \
    android.permission.ACCESS_FINE_LOCATION \
    android.permission.ACCESS_COARSE_LOCATION \
    android.permission.WRITE_EXTERNAL_STORAGE \
    android.permission.READ_EXTERNAL_STORAGE \
    android.permission.ACCESS_MEDIA_LOCATION; do
    adb -s "$serial" shell pm grant com.amaia23.hydracam "$perm" || true
  done
done
```

After boot, install the automation APK on each device and launch the app with the right role extras (see Section 2).

You can issue the same launch plan through the helper script:

```sh
python3 scripts/boot_and_verify_emulators.py --hydra-cluster --start
```

To boot the Hydra cluster, verify the shared `10.1.2.x` addresses, confirm
the emulators can reach each other, and then shut them all back down:

```sh
python3 scripts/smoke_test_shared_network.py
```

If that smoke test fails with only `10.0.2.15` / `10.0.2.16` showing up, use
host redirection instead of trying to force peer IPs. Android's emulator docs
recommend exposing the master on a host port and having the other emulator(s)
connect to `10.0.2.2:<host-port>`. For Hydra's automation build, the practical
pattern is:

```sh
# Expose the master's WebSocket server on the host
adb -s emulator-5554 forward tcp:4040 tcp:4040

# Launch slaves with a fixed master IP on the emulator host alias
adb -s emulator-5556 shell am start \
  -n com.amaia23.hydracam/.MainActivity \
  --es role slave --es preferredMasterIp 10.0.2.2 --ez forceSlaveMode true
```

This works with Hydra because `SlaveScreen` already supports `preferredMasterIp`
when the app is built with `--dart-define=HYDRACAM_AUTOMATION=true`.

## 2. Launch Devices

1. Start the emulators you need (first will become master by default):

    ```sh
    $ANDROID_HOME/emulator/emulator -avd Pixel_6_API_34 -port 5554 -shared-net-id 11 -no-snapshot -camera-back virtualscene &
    $ANDROID_HOME/emulator/emulator -avd Pixel_6_API_34 -port 5556 -shared-net-id 12 -no-snapshot -camera-back virtualscene &
    ```

1. Install the automation build on each device:

    ```sh
    adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
    adb -s emulator-5556 install -r build/app/outputs/flutter-apk/app-debug.apk
    ```

1. Launch HydraCam in automation mode (adds MethodChannel hooks and HTTP bridge):

   ```sh
   adb -s emulator-5554 shell am start \
     -n com.amaia23.hydracam/.MainActivity \
     --es role master
   adb -s emulator-5556 shell am start \
     -n com.amaia23.hydracam/.MainActivity \
     --es role slave \
     --es preferredMasterIp 10.0.2.2 \
     --ez forceSlaveMode true
   adb -s emulator-5558 shell am start \
     -n com.amaia23.hydracam/.MainActivity \
     --es role slave \
     --es preferredMasterIp 10.0.2.2 \
     --ez forceSlaveMode true
   adb -s emulator-5560 shell am start \
     -n com.amaia23.hydracam/.MainActivity \
     --es role slave \
     --es preferredMasterIp 10.0.2.2 \
     --ez forceSlaveMode true
   ```

## 3. Run the Orchestrator CLI

- Dry-run (set up adb forwards only):

  ```sh
  python3 scripts/multi_device_orchestrator.py \
    --serials emulator-5554:master,emulator-5556:slave \
    --dry-run
  ```

- Execute the default "smoke" scenario end-to-end:

  ```sh
  python3 scripts/multi_device_orchestrator.py \
    --serials emulator-5554:master,emulator-5556:slave
  ```

  This will:

  1. Forward local ports to the in-app automation bridge on each device.
  2. Wait for `GET /healthz` to report `{"status":"ok"}`.
  3. Call `/commands/start_session`, `/commands/take_photo`, and `/commands/end_session` on the master.
  4. Print JSON summaries of each command result.
  5. Persist device logs, session snapshots, and a `summary.json` under `automation_runs/<timestamp>-smoke/`.

Artifacts default to `automation_runs/`, but you can override with `--output-dir`.

### Scenario manifests (4-device orchestration)

Complex runs now live in JSON manifests under `automation_scenarios/`. Each manifest
declares:

- Optional top-level `context` values (strings can reference `{{timestamp}}`,
  `{{isoTimestamp}}`, etc.).
- A `steps` array where every entry carries an `action` plus targeting hints.
- Supported actions: `setContext`, `settings`, `command`, `await`, `sleep`, and `get`.
  Commands default to the master unless you pass `role`, `roles`, `serial`, or
  `targets: "all"`.

Example (excerpt from `automation_scenarios/quad_smoke.json`):

```json
{
  "name": "quad_smoke",
  "context": {"sessionId": "quad-{{timestamp}}"},
  "steps": [
    {"action": "settings", "targets": "all", "payload": {"autoUploadMaterials": true}},
    {"action": "command", "role": "master", "command": "start_session",
     "payload": {"sessionId": "{{sessionId}}"},
     "capture": {"sessionGuid": "sessionGuid"}},
    {"action": "command", "role": "master", "command": "take_photo",
     "payload": {"showCountdown": true}},
    {"action": "command", "role": "master", "command": "end_session"}
  ]
}
```

Run it alongside the four prepared emulators:

```sh
python3 scripts/multi_device_orchestrator.py \
  --serials \
    emulator-5554:master,emulator-5556:slave,emulator-5558:slave,emulator-5560:slave \
  --manifest automation_scenarios/quad_smoke.json \
  --scenario quad_smoke
```

During execution the orchestrator:

1. Applies adb forwarding + health checks (same as the smoke test).
2. Loads the manifest, interpolates placeholders, and executes each action in order.
3. Persists a step-by-step transcript inside `automation_runs/<ts>-quad_smoke/summary.json`.
4. Captures per-device session/log dumps plus backend re-downloads when the API info
   is provided.

### Backend verification toggle

Set the following env vars (or pass CLI flags) to enable automatic re-download of uploaded assets:

```sh
export HYDRACAM_API_BASE="https://api.hydracam.dev"
export HYDRACAM_AUTOMATION_TOKEN="<token>"

python3 scripts/multi_device_orchestrator.py \
  --serials emulator-5554:master,emulator-5556:slave \
  --backend-base-url "$HYDRACAM_API_BASE" \
  --backend-token "$HYDRACAM_AUTOMATION_TOKEN"
```

Successful runs leave `backend/session.json` plus the downloaded assets (with SHA-256 hashes) inside the run folder.

## 4. Manual Validation Hooks

The automation bridge exposes lightweight HTTP endpoints per device once the app is running with `HYDRACAM_AUTOMATION=true`:

- `GET http://127.0.0.1:<forwarded-port>/healthz` → readiness probe.
- `GET .../session` → session GUID, queued uploads, active status.
- `GET .../logs` → recent LogService entries.
- `POST .../settings` with `{"autoUploadMaterials": true}` etc. to mutate SharedPreferences-backed settings.
- `POST .../commands/<start_session|end_session|take_photo|start_recording|stop_recording>` to drive the master actions directly.

To inspect the state of the master after a scenario:

```sh
curl http://127.0.0.1:5900/session | jq
curl http://127.0.0.1:5900/logs | jq '.logs[-10:]'
```

(Default port base is 5900; adjust if you pass `--port-base`.)

## 5. Backend Verification (Phase 2 placeholder)

Backend calls now happen automatically when the API base/token are provided. The orchestrator:

1. Calls `GET /sessions/<guid>` and stores the JSON payload under `backend/session.json`.
2. Downloads each media asset referenced by `assets`, `media`, or `uploads` arrays.
3. Computes SHA-256 hashes and records them in the summary for quick comparison later.

You can still re-run manual checks with curl if needed.

## 6. Cleanup

- Stop the automation server via `adb emu kill` or closing the emulator windows.
- Remove adb port forwarding if needed: `adb -s <serial> forward --remove-all`.
- Collected artifacts will live under `automation_runs/` (to be added in Phase 2).

## 7. Quick Troubleshooting

- **Health check never returns**: ensure app launched with the automation dart-define and port 4762 isn’t blocked.
- **Command returns 404**: the master screen was not mounted (e.g., app stuck on slave role). Switch to master or force `--es role master` when launching.
- **Python script can’t find devices**: run `adb devices` manually; the script skips `offline` and `unauthorized` entries.
- **Need verbose logging**: tail `flutter logs -d <serial>` while invoking orchestration commands.

## 8. Lab configuration

Lab bridge IPs, expected Wi-Fi subnets, media-timeline URLs, and store URLs
used across scripts and both runbooks are documented in one place:
`config/lab.env.example`. Copy it to `config/lab.env` (git-ignored) and edit
values for your lab; `scripts/hydracam_lib/labconfig.py` reads that file with
real environment variables always taking precedence, and falls back to the
same hard-coded defaults scripts already use today if neither is present.

This is consultative only for now — no existing script reads `config/lab.env`
yet, so editing it does not change current script behavior. See the module
docstring in `scripts/hydracam_lib/labconfig.py` for the `get(key, default)`
API once scripts migrate to it.
