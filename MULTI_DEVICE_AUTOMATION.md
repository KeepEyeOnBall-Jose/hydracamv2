# HydraCam Multi-Device Automation Plan

## 1. Objectives

- Reproduce a realistic 1-master / N-slave capture session entirely via automation.
- Run everything from a single command that builds the app, launches emulators, orchestrates captures, and validates uploads against the HydraCam backend.
- Keep the plan CI-friendly (eventual nightly run) while still being reproducible on a developer laptop.

## 2. High-Level Architecture

| Layer | Responsibility | Notes |
| --- | --- | --- |
| Orchestrator CLI (Python) | Spins up emulators/physical devices, applies roles, drives test scenarios, collects artifacts. | Lives under `scripts/multi_device_orchestrator.py`. Data-driven JSON manifest. |
| Device Control Adapter | Communicates with each HydraCam instance via a MethodChannel bridge exposed only in automation builds. | Enables commands such as `start_session`, `take_photo`, `toggle_auto_upload`, `fetch_logs`. |
| HydraCam App (Automation Hooks) | Responds to automation RPC calls by invoking existing services (SessionManager, MasterServer, etc.). | Guarded by `--dart-define=HYDRACAM_AUTOMATION=true` so production builds remain untouched. |
| Backend Verifier | Uses HydraCam API to request artifacts for the recorded session(s) and re-download each file for byte comparison. | Reuses `HydraCamApiService` with injectable HTTP client + automation token override. |
| Report Generator | Summarizes per-scenario status, device logs, backend verification, and media hashes. | Output as JSON + Markdown for humans/CI. |

## 3. End-to-End Flow

1. **Build** the Flutter app once (`flutter build apk --debug`).
2. **Launch** requested emulators (default: 1 master + 3 slaves). Attach fake camera feeds via `adb emu camera`. Record emulator serials.
3. **Install & Boot** HydraCam with role-specific extras:

   ```bash
   adb -s <serial> install build/app/outputs/flutter-apk/app-debug.apk
   adb -s <serial> shell am start -n com.mobo.hydracam/.MainActivity \
     --es role master --ez automation true --es preferredMasterIp 10.0.2.2
   ```

4. **Register** devices inside the orchestrator (wait until MethodChannel handshake confirms automation bridge is ready).
5. **Execute Scenario Manifest** (P1–P5, V1–V5, variations). For each scenario:
   - Set timers / flash / auto-upload settings through RPC.
   - Trigger commands (`start_session`, `take_photo`, `start_recording`, `stop_recording`).
   - Await completion signals + metadata updates.
   - Pull session folders from each device for local inspection.
6. **Backend Verification**: once uploads finish, call `/sessions/{guid}` via HydraCam API, fetch returned media URLs, download them, and compare SHA-256 hashes with the captured files.
7. **Reporting & Cleanup**: emit JSON/Markdown summary, capture logcat snippets, and gracefully shut down emulators.

## 4. Automation Hooks Required in App

- `hydracam_automation` MethodChannel available only when compiled with `--dart-define=HYDRACAM_AUTOMATION=true`.
- Supported commands (initial pass):
  - `get_session_state` → returns guid, counts, pending uploads.
  - `set_setting` → toggles SharedPreferences-backed flags (auto-upload, timer duration, flash, etc.).
  - `start_session`, `end_session` (Master only) → call `MasterServer` APIs.
  - `take_photo`, `start_recording`, `stop_recording` (Master) → reuse existing logic, but honor scheduler.
  - `get_logs` → snapshot of `LogService` buffer.
- Bridge should log every automation call for traceability and respond with structured JSON.

## 5. Orchestrator CLI Design

```text
scripts/multi_device_orchestrator.py
├── EmulatorManager: create/start/stop, inject camera feed
├── DeviceSession: wraps adb serial + MethodChannel proxy (via `flutter drive` VM service or `frida`-style channel)
├── ScenarioRunner: loads YAML/JSON manifest and issues commands
├── BackendVerifier: queries HydraCam API and downloads assets
└── Reporter: compiles JSON/Markdown summaries
```

- Use `asyncio` + `adb` subprocesses to control multiple devices concurrently.
- Persist run artifacts under `automation_runs/<timestamp>/` (logs, pulled media, manifest, report).
- Provide CLI flags: `--devices`, `--manifest scenarios/default.json`, `--apk build/app/outputs/...`, `--backend-base-url`, `--auth-token`.

## 6. Backend Verification Strategy

- Reuse `HydraCamApiService` headers (`Authorization: Bearer <token>`). For automation, accept token via env var or orchestrator config.
- For each uploaded media entry returned by the API:
  1. Download file to `artifacts/backend/<guid>/<filename>`.
  2. Compute SHA-256 and compare with local captured file hash.
  3. Record mismatch with full context (deviceId, captureDate, URL).
- If backend reports extra/missing files vs. local expectation, mark scenario as failed.

## 7. Execution Entry Points

- `just e2e-multi` (or `make e2e-multi`) → ensures `flutter build apk`, then calls Python orchestrator.
- CI job: nightly cron on self-hosted runner with Android SDK, uses headless emulators (`-no-window`).

## 8. Phased Implementation

1. **Phase 1 (current)**: land automation bridge + Python orchestrator skeleton that can launch emulators and handshake with HydraCam (no media capture yet).
2. **Phase 2**: add full scenario execution (session start, photo/video, metadata polling).
3. **Phase 3**: integrate backend verification + artifact hashing.
4. **Phase 4**: polish reporting, CI integration, and resilience (retry logic, health checks).

## 9. Open Questions / Follow-Ups

- Preferred source for prerecorded camera feeds (per-device video loops)?
- How should secrets (Auth0 client credentials) be injected in CI? (likely GitHub Actions secrets passed as env vars.)
- Do we need to support physical devices alongside emulators in the same run? If so, orchestrator must accept a device manifest file.
- Expected run time budget per scenario—helps tune emulator warmup parallelism.

This document will evolve as we implement each phase; updates live alongside code changes for traceability.
