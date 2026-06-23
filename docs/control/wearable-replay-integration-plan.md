# Wearable Replay Integration Plan

Last reviewed: 2026-06-22.

This document is the durable control-plane plan for adding player-worn wearable
capture to HydraCam sessions. It covers Ray-Ban Meta no-display glasses,
Galaxy Watch4 telemetry, and media-timeline replay output.

## Product Contract

V1 is for private squash/padel match replay and content production. One
identified player wears Ray-Ban Meta glasses and a Galaxy Watch4. The paired
HydraCam phone owns both wearable streams and attaches them to the active
HydraCam capture session.

HydraCam remains the session authority. Wearables do not directly join the
master/slave mesh in v1. Instead, each wearable record carries the active
`sessionGuid`, one `participantId`, the wearable `sourceDeviceId`, the paired
HydraCam device id, local timestamp, shared-clock timestamp, sync confidence,
and publish/privacy flags.

Share-ready replay output is the default product lane: glasses audio is on by
default, HR/motion overlays are included by default, and media-timeline must
gate public export through explicit pre-publish review and consent state. The
heart-rate and exertion language is fitness/wellness only; do not make medical,
diagnostic, or competition-compliance claims.

## Capture And Feedback Scope

- Galaxy Watch4 v1 captures heart-rate telemetry, motion samples, player marker
  events, recording/sync status, and between-point haptic confirmations.
- Ray-Ban Meta v1 targets continuous POV video/audio capture through Meta
  Wearables Device Access Toolkit. If continuous capture is not reliable under
  developer-preview access, use a rolling highlight buffer and preserve the same
  timeline contract.
- Feedback v1 is limited to capture-state cues: recording started/stopped, sync
  ready/degraded, marker saved, and highlight created. No tactical coaching
  prompts are included in v1.
- The no-display Ray-Ban Meta model has no visual glasses overlay. Use glasses
  audio, watch haptics, and phone/operator UI only.

## Local Data Contract

HydraCam persists wearable replay data beside existing session files under:

```text
session_<sessionGuid>/
  metadata.json
  <media>.sync.json
  wearables/
    tracks/<trackId>.json
    samples/<trackId>-chunk-0000.jsonl
    calibration/<calibrationId>.json
    markers/<markerId>.json
    pov/<recordingId>.json
    pov-media/<recordingId>.<ext>
    feedback/<feedbackId>.json
    wearable-upload-manifest.json
```

The first mock-first implementation lives in:

- `lib/models/wearable_replay.dart`
- `lib/services/wearable_replay_service.dart`
- `lib/services/wearable_replay_bridge_service.dart`
- `lib/services/wearable_replay_simulation_service.dart`
- `lib/services/wearable_replay_upload_service.dart`

`WearableReplayService` writes bounded JSONL sample chunks, discrete
calibration / marker / POV / feedback sidecars, stages existing POV media into
`wearables/pov-media/`, and writes a media-timeline-oriented upload manifest.
The manifest declares the replay intent: register POV as another angle, render
audio on by default, render HR and motion overlays, and require pre-publish
review.

Native mock bridges are now registered on both phone platforms:

- Android: `android/app/src/main/kotlin/com/amaia23/hydracam/MainActivity.kt`
- iOS: `ios/Runner/AppDelegate.swift`

Both bridges expose `hydracamv2/wearable_replay` with mock capabilities,
synthetic Watch4 HR/motion readings, mock Ray-Ban Meta POV capture files, and
capture-state feedback acknowledgements. `metaDatAvailable` is intentionally
`false` until physical Meta DAT access is verified; `metaMockAvailable` and
`watchMockAvailable` are the emulator/simulator proof lane. When DAT is not
available, the simulation path requests `rollingHighlight` POV capture and
persists `fallbackReason: meta_dat_unavailable_simulated_rolling_buffer` in the
POV track/recording metadata instead of claiming continuous full-match DAT
capture.

Platform DAT registration plumbing is also pre-wired without adding private SDK
artifacts to normal builds:

- Android declares `BLUETOOTH_CONNECT`, developer-mode
  `com.meta.wearable.mwdat.APPLICATION_ID=0`, analytics opt-out, and a distinct
  `com.amaia23.hydracam.mwdat` callback scheme through Gradle manifest
  placeholders.
- iOS declares the `com.keepeyeonball.mwdat` callback scheme, `MWDAT`
  developer-mode `MetaAppID=0`, analytics opt-out, `fb-viewapp` query support,
  `com.meta.ar.wearable` external accessory protocol, Bluetooth usage text, and
  the Bluetooth/external-accessory background modes required by the public DAT
  setup guide.

Do not add `mwdat-core` / `mwdat-camera` / `mwdat-mockdevice` or the iOS
`MWDATCore` / `MWDATCamera` / `MWDATMockDevice` packages to default builds.
The local GitHub token now has Android DAT package access, but the SDK artifacts
should stay gated behind the physical DAT lane until a reachable paired phone
and Ray-Ban Meta device can prove the stream path without regressing the
mock/fallback lane.

Use the wearable readiness checker to keep that boundary explicit:

```bash
python3 scripts/check_wearable_replay_readiness.py mock
python3 scripts/check_wearable_replay_readiness.py dat
```

`mock` must pass before claiming emulator/simulator readiness. Offline `dat`
must pass before claiming the repo-controlled Meta DAT registration and
dependency boundary is ready. Add `--check-network` in `dat` mode when entering
the physical Meta DAT lane; that explicit external check requires
`GITHUB_TOKEN` or `GH_TOKEN` with GitHub Packages `read:packages` scope.

The first Wear OS companion surface is isolated in the Android Gradle module:

- `android/wearable/build.gradle`
- `android/wearable/src/main/kotlin/com/amaia23/hydracam/wearable/WearMainActivity.kt`
- `android/wearable/src/main/kotlin/com/amaia23/hydracam/wearable/WearTelemetrySample.kt`
- `android/wearable/src/main/kotlin/com/amaia23/hydracam/wearable/HealthServicesWearTelemetrySource.kt`

The watch module builds as `com.amaia23.hydracam.wearable`, targets Galaxy
Watch4-class Wear OS devices with `minSdk 30`, declares body-sensor/activity
recognition/vibration permissions, and keeps the UI focused on status, marker,
sync cue, and capture confirmation controls. It requests watch sensor
permissions at runtime, registers a Wear OS Health Services `MeasureClient`
heart-rate stream when available, merges that with standard accelerometer and
gyroscope snapshots, and falls back to the mock stream when Health Services or
permissions are unavailable. Its simulation source emits HydraCam-compatible
HR/motion payloads, marker payloads, feedback payloads, and clap/flash
calibration results. The Health Services implementation uses
`androidx.health:health-services-client:1.1.0-rc02`; the remaining Watch4 gate
is physical pairing/permission/stream proof.

## Sync And Proof

Wearable timestamps use the existing HydraCam `SyncMetadata` contract:

```text
sharedClockTimestamp = localTimestamp + syncMetadata.offsetMs
```

The target remains frame-level alignment: `<= 50 ms` across HydraCam cameras,
glasses POV, and watch telemetry. A private-match or staged-match evidence pack
must include a short clap/flash calibration ritual visible or audible to the
available capture devices, then record the measured alignment error and sync
confidence.

## Implementation Phases

1. **Mock-first local contract:** models, sidecar persistence, upload manifest,
   and focused tests using synthetic watch samples and mock POV metadata.
2. **Galaxy Watch4 app:** add a Wear OS companion module for marker/status UI,
   HR via Wear OS Health Services, and standard motion sensors. Use Samsung
   Health Sensor SDK only if standard APIs cannot supply the needed data.
3. **Meta DAT bridges:** add Android/iOS native bridges for Ray-Ban Meta camera
   and audio streaming. Verify developer-preview access, app registration,
   credentials, and physical pairing before treating continuous POV as
   available.
4. **media-timeline replay:** register wearable tracks through File Registry and
   event media/assets, render POV as a replay angle, show HR/motion/marker
   overlays, and gate export through review/consent state.
5. **Full hardware evidence:** run Ray-Ban Meta, Galaxy Watch4, Android phone,
   iPhone, and at least one HydraCam camera device in one evidence pack.

## Verification Gates

- Dart model tests for serialization, shared-clock timestamp calculation, sync
  confidence propagation, and publish/review defaults.
- Flutter service tests for active-session rejection, bounded sample chunks,
  marker/POV/feedback sidecars, and upload manifest generation.
- Bridge tests for native capabilities, Watch4 telemetry mapping, Meta POV
  start/stop, watch haptic plus glasses audio feedback delivery, and
  missing-channel fallback.
- Upload-shape tests for media-timeline bridge multipart payloads, including
  track sidecars, telemetry chunks, marker sidecars, POV sidecars, session-local
  POV media, feedback sidecars, and replay intent metadata.
- Android emulator and iOS simulator integration tests for the native mock
  channel before any hardware claims.
- media-timeline backend tests for wearable replay ingest and POV replay-angle
  event-media registration.
- Hardware evidence under `logs/verification-runs/<run>/` before claiming
  wearable replay works on physical devices.

Current non-hardware proof, last run 2026-06-22 after restarting
`Hydra_Master_API34`:

```bash
python3 scripts/run_wearable_replay_non_hardware_proof.py \
  --run-id 20260622-1831-wearable-replay-non-hardware-proof

flutter test --no-pub \
  test/models/wearable_replay_test.dart \
  test/services/wearable_replay_service_test.dart \
  test/services/wearable_replay_bridge_service_test.dart \
  test/services/wearable_replay_simulation_service_test.dart \
  test/services/wearable_replay_upload_service_test.dart \
  test/services/wearable_replay_live_upload_test.dart

flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter build ios --simulator --no-pub

flutter test --no-pub integration_test/wearable_replay_channel_test.dart \
  -d emulator-5554

flutter test --no-pub integration_test/wearable_replay_channel_test.dart \
  -d 6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3

cd /Users/jose/src/work/media-timeline/backend && \
  npx vitest run \
    src/services/hydraCamBridgeTypes.test.ts \
    src/services/hydraCamBridgeService.test.ts \
    src/routes/hydraCamBridge.test.ts

cd /Users/jose/src/work/media-timeline/backend && npm run build

cd /Users/jose/src/work/hydracamv2/android && \
  JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home \
  ./gradlew :wearable:testDebugUnitTest :wearable:assembleDebug

cd /Users/jose/src/work/media-timeline/frontend && \
  npm run test -- src/components/VideoExplorerTable.test.tsx

python3 -m unittest scripts/test_wearable_replay_readiness.py
python3 scripts/check_wearable_replay_readiness.py mock
python3 scripts/check_wearable_replay_readiness.py dat
```

The packaged evidence run
`logs/verification-runs/20260622-1831-wearable-replay-non-hardware-proof/`
passed and wrote `summary.md`, `summary.json`, command logs, enriched media,
and browser proof artifacts. It is the current proof that the wearable replay
slice works in emulation/simulation and against the local media-timeline replay
surface.

The local live media-timeline handoff proof is gated so normal test runs stay
offline by default:

```bash
flutter test --no-pub \
  --dart-define=HYDRACAM_WEARABLE_LIVE_UPLOAD=true \
  --dart-define=HYDRACAM_MEDIA_TIMELINE_API_BASE_URL=http://127.0.0.1:3001/api \
  test/services/wearable_replay_live_upload_test.dart
```

The Android run used `Hydra_Master_API34` / `emulator-5554`. The iOS run used
the iPhone 16 Pro simulator `6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3` on iOS
18.4. Both integration runs passed native mock capabilities, watch telemetry,
rolling-highlight POV fallback file creation, and watch haptic plus glasses
audio feedback acknowledgement.
The Wear OS module unit/build proof includes the real Health Services
registration path, runtime sensor-permission request path, standard motion
sensor path, and mock fallback path; it does not prove physical heart-rate
delivery until a Galaxy Watch4 is paired and granted `BODY_SENSORS`.
The wearable readiness checker currently passes the `mock` lane with 56 checks
and the offline `dat` lane with the repo-controlled DAT registration and
dependency-boundary checks. The explicit external Android DAT package-access
gate is:

```bash
GH_TOKEN="$(gh auth token)" python3 scripts/check_wearable_replay_readiness.py dat --check-network
```

The media-timeline backend accepts the generated wearable manifest, sidecars,
and POV media at `/api/hydracam-bridge/compat/sessions/upload-wearables`, then
registers POV as replay-angle event video media with wearable overlay metadata.
The media-timeline enriched event media endpoint now carries that wearable
metadata through to the existing event video table, which renders POV replay,
HR, motion, audio, sync, and pre-publish-review status in the replay column.
The selected media-timeline video detail player also loads the enriched
wearable replay record for the chosen POV asset and renders the replay sync,
telemetry, audio, and pre-publish-review overlay during playback.
Live local backend/browser proof on 2026-06-22 posted a synthetic wearable
bundle to media-timeline and created event
`hydracam-6049fec8-e6ea-44f9-aab4-22d316a969fe` with POV file id
`b9224605-66d3-42de-8de7-3c1f10831609`; the enriched media response included
`wearableReplay.replayAngle: true`, HR/motion/marker overlay flags, audio,
review, and green sync confidence. A headless browser check of
`http://localhost:5173/events/hydracam-6049fec8-e6ea-44f9-aab4-22d316a969fe/details`
rendered `1 POV replay`, `POV`, `HR`, `Motion`, `Audio`, and `Review` with no
warning/error console messages.
A headless browser check of
`http://localhost:5173/events/hydracam-6049fec8-e6ea-44f9-aab4-22d316a969fe/videos/b9224605-66d3-42de-8de7-3c1f10831609`
rendered the selected playback overlay with `POV replay`, `Ray-Ban Meta`,
`Continuous`, `Sync green`, `HR`, `Motion`, `1 markers`, `1 samples`,
`Audio on`, and `Pre-publish review` with no failed responses or browser
console warning/error messages after `audio-service` was started through
Service Monitor.
The remaining gates for the current v1 mock-first slice are the physical Meta
DAT lane (developer-preview package access plus Ray-Ban Meta pairing), physical
Galaxy Watch4 pairing/permission/Health Services streaming, and a full
real-device evidence pack.

On 2026-06-22 the gated live proof generated the manifest from HydraCam's
`WearableReplayService`, uploaded it through `WearableReplayUploadService`, and
verified media-timeline event `hydracam-wearable-live-1782142793799261` with
POV file id `33c26fa3-afb0-4614-baf4-23f86120b7bd`. The enriched row reported
`captureMode: rollingHighlight`, audio on, review required, green sync,
2 tracks, 2 sample chunks, 3 samples, 1 clap/flash calibration, 1 marker, and
2 feedback events across watch haptic and glasses audio confirmation channels.
A headless browser check of
`http://localhost:5173/events/hydracam-wearable-live-1782142793799261/videos/33c26fa3-afb0-4614-baf4-23f86120b7bd`
rendered `POV replay`, `Ray-Ban Meta`, `Rolling Highlight`, `Sync green`, `HR`,
`Motion`, `1 markers`, `3 samples`, `1 calibration`, `2 feedback cues`,
`Audio on`, and `Pre-publish review` with no failed HTTP responses or browser
console warning/error messages. The only Playwright request failure was the
processing-status SSE stream aborting when the headless browser closed.

The latest rerun after the Android emulator restart generated
`hydracam-wearable-live-1782146206076001` with POV file id
`b0db1ea1-d08b-4603-8509-63a606e6f3d1`. `GET
/api/events/hydracam-wearable-live-1782146206076001/media/enriched` returned
`wearableReplay.replayAngle: true`, `captureMode: rollingHighlight`, audio on,
review required, green sync, 2 tracks, 2 sample chunks, 3 samples, 1
clap/flash calibration, 1 marker, and 2 feedback events. A headless browser
check of
`http://localhost:5173/events/hydracam-wearable-live-1782146206076001/videos/b0db1ea1-d08b-4603-8509-63a606e6f3d1`
rendered `POV replay`, `Ray-Ban Meta`, `Rolling Highlight`, `Sync green`, `HR`,
`Motion`, `1 markers`, `3 samples`, `1 calibration`, `2 feedback cues`,
`Audio on`, and `Pre-publish review` with no failed HTTP responses and no
browser warning/error console messages after label-store was started on
`3004`.

The external DAT package-access probe now passes with the current GitHub token:

```bash
GH_TOKEN="$(gh auth token)" python3 scripts/check_wearable_replay_readiness.py dat --check-network
# PASS: Android DAT GitHub Package access - HTTP 200
```

Physical hardware proof attempt
`logs/verification-runs/20260622-1915-wearable-replay-real-device-clap-flash/`
advanced the lane by confirming that DAT entitlement and `:wearable:assembleDebug`
both pass, then blocked truthfully on device availability: `adb devices -l` and
ADB mDNS showed no Android/Wear OS target, Bluetooth inventory showed no
connected Ray-Ban Meta or Galaxy Watch4, and CoreDevice listed the physical
iPhone/iPad as unavailable while Flutter reported code `-27`.

The 2026-06-23 physical rerun
`logs/verification-runs/20260623-0335-wearable-replay-real-device-rerun/`
narrows the blocker. Attached Android phones, the wireless iPhone, and the
wireless iPad were visible; DAT readiness passed in mock, offline DAT, and
network package-access modes; and the Wear OS module built successfully when run
with the Flutter-configured JDK 17. `RF8M21J8XRT` showed bonded Watch4 and
RB Meta entries, but Bluetooth state was disconnected, no Wear OS ADB target was
visible, and no physical DAT or Health Services stream could be captured. The
remaining gate is active wearable connection/stream reachability, not repo
readiness.

The follow-up same-day evidence pack
`logs/verification-runs/20260623-1518-wearable-replay-real-device-phone-connected/`
proves the active paired phone state. Flutter saw three physical Android phones,
the iPhone, the iPad, emulator, simulator, macOS, and Chrome. `RF8M21J8XRT`
reported connected Bluetooth devices `Watch4 von Jose Ramon` and `RB Meta 00D5`,
installed `com.facebook.stella`, Samsung Watch Manager, Samsung Health Monitor,
and HydraCam `com.amaia23.hydracam` version `1.4.0`/`versionCode=19`. The pack
includes a real screenshot and short screen recording from that phone. Full
wearable replay is still partial because no Wear OS ADB target is visible for
installing/granting `BODY_SENSORS`, and the phone app still exposes the
mock/fallback Ray-Ban bridge rather than a real DAT SDK capture stream.

The 2026-06-23 follow-up
`logs/verification-runs/20260623-1538-watch4-wearos-adb-hr-stream/` clears the
Galaxy Watch4 ADB gate on physical hardware. The Watch4 `SM-R875F`
(Wear OS API `36`) was paired and connected over wireless ADB at
`192.168.178.117:41145`, the `:wearable` module was installed on the watch, and
`WearMainActivity` ran on-device. The first launch surfaced a real bug: Health
Services `MeasureClient` registration failed with
`Missing permissions: [android.permission.health.READ_HEART_RATE]` because the
module declared only legacy `BODY_SENSORS`. On Wear OS 5+/API 35+ the
heart-rate stream additionally requires `android.permission.health.READ_HEART_RATE`.
After declaring/requesting that permission and re-granting, the status changed
to `Health Services HeartRate availability: ACQUIRING` with live motion samples
and no registration failure. `HR 0 bpm` is expected off-body; Health Services
reports `ACQUIRING` and withholds BPM until skin contact. The only remaining
Watch4 step is a wrist-worn capture for a non-zero heart-rate sample; ADB
install, permission grant, Health Services registration, and the motion stream
are now proven on hardware.

## External Dependencies

- Meta Wearables Device Access Toolkit is developer preview. Start each
  hardware pass by verifying access, application id, SDK credentials, developer
  mode, physical pairing, and mock-device fallback.
- Wear OS Health Services is the default Galaxy Watch4 integration path.
  Samsung Health Sensor SDK is optional and Galaxy Watch-specific; do not make
  it mandatory unless HR/motion requirements cannot be met otherwise.
