# HydraCam Multi-Device Capture Validation Plan

## 1. Objectives

1. Prove that one master device can reliably orchestrate up to **four** slave devices (physical devices or emulators) for synchronous photo and video capture.
2. Exercise every meaningful permutation of:
   - Number of active devices (1–4)
   - Role assignment (master/slaves, rotating master)
   - Media type (photo vs. short video vs. long video)
   - Flash on/off, camera quality, auto-upload toggles, and gallery persistence
   - Network health (stable, dropped, rejoined)
3. Verify that each capture is:
   - Stored locally in the correct session folder
   - Pushed to the HydraCam album via `GalleryPersistenceService`
   - Uploaded to the MoBo API (via `UploaderService` logs and API responses)
4. Build the foundation for automated multi-emulator tests that we can later hook into CI.

## 2. Environment & Tooling

- **Emulators / Devices**: 4 Android emulators (Pixel 6 API 34 recommended) OR 3 emulators + 1 physical device.
- **Fake Camera Streams**: Use Android Emulator Extended Controls → "Camera" to feed prerecorded video loops (one unique loop per emulator to help visually confirm).
- **Networking**: All devices must share the same network (use host-only + NAT). Master should host hotspot equivalent by binding to `0.0.0.0:4040`.
- **Automation Harness (future)**: `adb` + `flutter drive`/`integration_test` + custom orchestrator script (Node/Python) that:
  - Boots emulators with `emulator -avd <name> -writable-system`
  - Installs debug APK once
  - Launches master/slave instances with role-specific deep links or runtime flags
  - Sends OSC/HTTP commands to simulate UI presses if needed (e.g., `adb shell input tap`)

## 3. Scenario Matrix (Photo)

| Scenario ID | Devices | Roles | Media | Flash | Auto Upload | Expectations |
| --- | --- | --- | --- | --- | --- | --- |
| P1 | 1 master, 1 slave | Master: Pixel6-M; Slave: Pixel6-S1 | Photo burst (3 shots) | Off | On | Master command triggers simultaneous captures; photos appear under session on both devices; upload queue drains with success logs. |
| P2 | 1 master, 2 slaves | Master: Pixel6-M; Slaves: S1,S2 | Staggered photo (S1 immediate, S2 after delay) | On | On | Flash toggles for each capture; HydraCam album shows 2 entries per slave; metadata JSON lists both photos. |
| P3 | 1 master, 3 slaves | Master: Pixel6-M; Slaves: S1,S2,S3 | Round-robin (each slave commanded individually) | Off | Off | Master issues targeted commands (deviceId). Each slave stores but uploader queue stays pending (auto-upload off). Verify manual upload works afterwards. |
| P4 | 1 master, 4 devices | Master rotates every session | Photo sequences per master rotation | Mixed | On | Validate master handoff: session ends, new master starts, slaves reconnect automatically. |
| P5 | Low battery test | Master: Pixel6-M (battery <20%), Slaves: S1,S2 | Photo burst | Off | On | Battery snackbar warns once; capture still proceeds; ensure no duplicate warnings (<5 min window). |

## 4. Scenario Matrix (Video)

| Scenario ID | Devices | Roles | Media | Duration | Storage Stress | Expectations |
| --- | --- | --- | --- | --- | --- | --- |
| V1 | 1 master, 1 slave | Start/stop video simultaneously | 5s clip | Short | Normal | Session stores video on both devices, `onVideoRecorded` callback fires; upload success. |
| V2 | 1 master, 2 slaves | Master records, slaves record | 20s clip | Medium | Normal | Confirm `GalleryPersistenceService.saveVideo` called for each path; check `SessionManager` metadata. |
| V3 | 1 master, 3 slaves | Rolling starts (S1 start, after 2s S2, after 4s S3) | 15s clip | Medium | Normal | Validate scheduler accuracy; each slave logs scheduled start within +/-200ms. |
| V4 | 1 master, 4 slaves | Start/stop multiple times | 4 clips × 8s | High | Critical | StorageService forced stop triggered mid-run (<0.5GB). CameraService stops and logs interruption; UI warns user; uploads only completed clips. |
| V5 | Upload resilience | 1 master, 2 slaves | 30s clip per device | High | Stress | Simulate network drop mid-upload (disable Wi-Fi). Uploader retries, queue drains once network restored. |

## 5. Cross-Cutting Variations

1. **Role Rotation**: After every session, choose a different master (S1 → master, others follow). Confirms discovery service recovers.
2. **Device Count Scaling**: Start with 2 devices, add third mid-session, remove fourth (disconnect). Ensure heartbeat removal works.
3. **Gallery Permission Denial**: Deny Photos permission on one device to see fallback logging (still saves to session folder, warns about missing album write).
4. **Auto-Upload Toggle**: Switch `autoUploadMaterials` off mid-session, take photo, then toggle on and ensure queue resumes.
5. **Flash Announcement**: For video start/stop, confirm flash double-blink occurs only on devices with hardware flash.
6. **Manual Upload Trigger**: After capturing with auto-upload off, open uploader screen and manually start upload. Validate progress events.
7. **Low Storage**: Use emulator disk limit to 300MB to trigger `StorageService` critical path; verify recording blocked and forced stop path.
8. **Battery Drain**: Use `adb shell dumpsys battery` to set low level (e.g., 10%) on a slave; ensure snackbar warning appears once.

## 6. Detailed Execution Plan Per Session

1. **Session Bootstrap**
   - Launch emulators (`emulator @Pixel6_S1 &` ...). Wait until fully booted.
   - `adb -s <device> install build/app/outputs/flutter-apk/app-debug.apk`
   - Start HydraCam with deep links: `adb shell am start -n com.mobo.hydracam/.MainActivity --es role master`
   - For slaves: same command with `--es role slave --es preferredMasterIp 10.0.2.2`
2. **Discovery Verification**
   - Open log screen (`LogService`), ensure "Listening for master broadcast" and "Connected to master" entries.
   - On master, confirm list of connected device IDs equals expected count.
3. **Photo Flow**
   - Use UI automation or `adb input tap` to press "Take Photo".
   - Check each slave UI for overlay snapshot list update, HydraCam album entry, and `SessionManager` metadata via `adb pull /sdcard/Android/data/.../session_<guid>/metadata.json`.
   - Validate uploader logs: `Media added to upload queue` followed by `Media uploaded successfully` (if auto-upload on).
4. **Video Flow**
   - Configure timer (Settings → Timer Duration) for scheduled start.
   - Start `startRecordingVideo`, observe countdown. After clip, confirm `CapturedVideo` objects stored with correct start/end.
   - Pull video files and ensure size > 0 and `GalleryPersistenceService` logs success.
5. **Upload Confirmation**
   - Monitor API logs or mock API endpoint to assert `upload-media` requests per file.
   - Optionally set test server to respond with `200` and capture payloads for verification.
6. **Teardown / Rotation**
   - On master, tap "End Session"; ensure slaves receive `sessionEnded` command and clear session state.
   - Rotate roles (promote S1 to master) and repeat flows.

## 7. Automation Blueprint

1. **Coordinator Script** (Python):
   - `Device` class (id, role, adb serial, stream source).
   - Methods: `launch_emulator`, `set_role`, `trigger_photo`, `trigger_video`, `pull_metadata`, `collect_logs`.
   - Sequence definitions referencing scenarios P1–V5.
2. **Integration Tests** (`integration_test/multi_device_flow_test.dart`):
   - Use `integration_test` binding + custom platform channel to talk to host script.
   - Stages: `setupDevices`, `startSession`, `issueCommand`, `awaitMedia`, `assertUploads`.
3. **Mock API Option**: Stand up local server to capture uploads (if MoBo API not reachable in test env). Configure `HydraCamApiService` base URL via env flag.
4. **Result Aggregation**: After each scenario, produce JSON report (`scenarioId`, `devices`, `mediaCounts`, `failures`). Feed into CI artifacts.

## 8. Immediate Next Steps

1. Finalize coordinator script requirements (CLI, device mapping file, video feed config).
2. Implement `integration_test/multi_device_flow_test.dart` skeleton with host-bridge stubs.
3. Add instrumentation hooks in app for test mode (e.g., `--dart-define=TEST_DEVICE_ID=<id>` to bypass manual role selection).
4. Create mock API service toggle (HTTP server) for deterministic upload validation.
5. Pilot Scenario P1 + V1 manually; document timings and deviations.
6. Expand automation to cover rest of matrix iteratively.
