# HydraCam Status and Roadmap

Last control-plane migration: 2026-06-05.
Last status refresh: 2026-06-07.

This document is scoped to `/Users/jose/src/work/hydracamv2`, the Flutter mobile
repo. Backend, web, Azure, and AI/product work is recorded only when it blocks
or informs the mobile app.

## Current Mobile Status

| Area | Status | Notes |
| --- | --- | --- |
| iOS simulator | Runs, but no camera | 2026-06-07 simulator run applied camera settings after camera/mic privacy grants, but Flutter `camera` reported no available cameras. Use simulator for launch/UI checks only, not capture proof. Latest parallel matrix kept it launch-only on bridge port `4771`. Evidence: `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md`. |
| iOS physical device | Working in debug automation; profile install/launch partial | The prior broad white-screen blocker is superseded. `logs/verification-runs/2026-06-06-iphone-personal-team-debug/` shows iPhone 12 Pro debug launch, permissions, session creation, photo capture/upload, and video start. `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md` shows iPhone 12 Pro / iOS 26.5 passing the coordinated independent-capture matrix at `ultraWide` + `sport1080p60`, and iPad 5 passing `autoBack` + `standard1080p30`. `logs/verification-runs/20260607-1501-ios-icon-profile-launch/` shows Profile build/install passed and no-tooling `--no-activate` launch started `Runner.app/Runner`; foreground icon-equivalent activation still needs the iPhone unlocked. Limitation: saved-video metadata remains unavailable on iOS. |
| Android | In development; current camera evidence mixed | 2026-06-07 parallel matrix: both Samsung S10e devices and Samsung SM-G960F captured one photo and one video at `standard1080p30` under a shared capture barrier. Samsung S7 edge still fails at `standard1080p30` with bounded photo timeout plus Exynos/Camera2 reopen errors, now classified as `s7_exynos_camera_timeout`. Xiaomi 2201116PG install is still blocked by `INSTALL_FAILED_USER_RESTRICTED`. Evidence: `logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/summary.md`. |
| Camera lens/profile settings | Implemented; device proof partial | 2026-06-07 added local lens preference and target video profiles from 480p30 through 4K60. The video profile selector now shows concrete target text (`1080p at 30 fps`, `1080p at 60 fps`) instead of arbitrary names; the latest parallel matrix confirms `/settings.videoCaptureTarget` on macOS, Android, iPhone, and iPad. iPhone 12 Pro 0.5x debug automation passes 1080p60 and 4K30 targets, but iOS metadata extraction is still unavailable and S7 rear-wide 1080p60/4K30 remains blocked by basic capture failure. ASAP item 0 remains open. |
| Mobile login/auth | Imperfect | Current Auth0 login uses a browser-backed OAuth flow and stores user state only in memory. Login restore, secure credential persistence, logout/end-session behavior, Android process-death recovery, and Android-native account-picker UX are not complete. |
| Desktop and web | macOS controller debug path working; capture deferred | macOS debug `.app` builds and launches for controller/monitoring use with a mock local camera. Windows, Linux, web, and real desktop webcam capture remain future support. |
| Multi-device capture | Runtime role switching smoke passed; full physical matrix pending | Master/slave WebSocket flow exists. `logs/verification-runs/20260607-runtime-role-switch-local-smoke-timed/summary.json` proves a filtered macOS + iOS simulator run can launch once in standby, switch roles through automation, and connect one slave without relaunching. Full physical master/slave capture matrix still needs fresh evidence. |
| Store distribution | Prepared, not submitted | Distribution runbook and scaffolding exist; real submission depends on signing, credentials, privacy review, and device smoke tests. |

## Latest One-by-One Device Rerun

Evidence root: `logs/verification-runs/20260607-all-devices-one-by-one-rerun/`.

2026-06-07 current results:

- macOS passed the mock/controller capture repro at `autoBack` +
  `standard1080p30`.
- iOS simulator launched and started the automation bridge, but Flutter reported
  no available cameras; keep it as launch/UI evidence only.
- Physical iPad passed on a clean bridge-discovery run with `autoBack` +
  `standard1080p30`, one photo, one video, and recording false after stop.
  Saved-video metadata remains unavailable.
- At that time, iPhone 12 Pro was blocked: clean bridge-discovery run built and
  entered Xcode install/launch but no automation bridge appeared; direct
  `devicectl` launch was denied because the phone was locked.
- Samsung S10e passed `autoBack` + `standard1080p30`, including inactive session
  completion.
- Samsung S7 edge failed the baseline `compat720p30` capture before photo save;
  logcat shows repeated `ExynosCamera3` wait timeouts.
- Xiaomi 2201116PG remains blocked before app launch by
  `INSTALL_FAILED_USER_RESTRICTED`.

The first iPad/iPhone auto-discovery attempts in that evidence root are marked
invalid because they discovered the S10e bridge. Use the `clean-bridge` iPad and
iPhone directories for current iOS evidence.

Follow-up blocker rerun:
`logs/verification-runs/20260607-remaining-blockers-rerun/summary.md` records
fresh checks for the three still-unverified devices. Samsung S7 edge still
fails before photo save even at `dataSaver480p30`; at that time iPhone 12 Pro
direct launch was denied because the phone was locked; Xiaomi still fails debug
APK install with `INSTALL_FAILED_USER_RESTRICTED`. The later new-devices rerun
below supersedes the iPhone lock blocker for debug automation capture.

## Latest New-Devices Rerun

Evidence root: `logs/verification-runs/20260607-new-devices-rerun/`.

2026-06-07 fresh-device results:

- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60` debug
  automation capture: one photo, one video, recording stopped, bridge
  `http://192.168.178.141:4762`, iOS-native trace path under `/var/mobile/`.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `detail4k30` debug automation
  capture with the same selected 0.5x camera id. Saved-video metadata was still
  unavailable for both iPhone runs.
- New Samsung SM-G970F / Android 12 (`RF8M21J8XRT`) passed `autoBack` +
  `standard1080p30`, captured one photo and one video, ended the session, and
  logged recorded video metadata as `1920x1080, unknown fps, 3966 ms`.
- New Samsung SM-G960F / Android 10 (`29d816ac550b7ece`) failed before photo
  save at both `standard1080p30` and `compat720p30`; logs show CameraX
  `ImageCaptureException: Not bound to a valid Camera` after camera `0`
  initialization.
- Samsung S7 edge / Android 8 (`9885e6503930304946`) still failed before photo
  save even at `dataSaver480p30`; app logs show a 12 second photo timeout and
  logcat shows ExynosCamera3 wait timeouts plus Camera2 reopen / max-camera
  errors.

## Latest Post-Label Device Matrix

Evidence root: `logs/verification-runs/20260607-post-label-device-matrix/`.

This run verifies the device matrix after replacing video-profile display names
with concrete target labels.

- macOS passed `autoBack` + `standard1080p30`; `/settings` reported
  `videoCaptureTarget: 1080p at 30 fps`.
- Samsung S10e devices `RF8M90QE7LX` and `RF8M21J8XRT` passed `autoBack` +
  `standard1080p30`, ended their automation sessions, and logged
  `1920x1080, unknown fps` metadata.
- Samsung SM-G960F / Android 10 (`29d816ac550b7ece`) passed `autoBack` +
  `standard1080p30` on the current APK, with `1920x1080, unknown fps` metadata.
  This supersedes the earlier G960F failure in the new-devices rerun.
- Samsung S7 edge / Android 8 (`9885e6503930304946`) still failed before photo
  save at `standard1080p30`; app logs show a 12 second timeout and logcat shows
  ExynosCamera3 / Camera2 reopen errors.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60`; `/settings`
  reported `videoCaptureTarget: 1080p at 60 fps`. Saved-video metadata remained
  unavailable.
- Physical iPad / iOS 15.6.1 passed `autoBack` + `standard1080p30` only in the
  explicit-host run at `192.168.178.104`; auto-discovered iPad artifacts in
  this root are invalid because they attached to the iPhone bridge. Saved-video
  metadata remained unavailable.
- iOS simulator launched and exposed the automation bridge, but it remains
  launch/UI-only because Flutter reported no cameras available.

## Latest Parallel Device Matrix

Evidence root:
`logs/verification-runs/20260607-parallel-device-matrix-staged-logcat/`.

This run validates independent local capture on all connected targets through a
shared capture barrier. It intentionally launched each capture-capable device as
a local master to prove lens/profile/capture settings per device; it is not a
master/slave discovery or synchronized broadcast proof.

- Shared barrier released at `2026-06-07T16:06:09.664388`.
- iPhone 12 Pro / iOS 26.5 passed `ultraWide` + `sport1080p60`;
  `/settings` reported `videoCaptureTarget: 1080p at 60 fps`.
- iPad 5 / iOS 15.6.1 passed `autoBack` + `standard1080p30` through explicit
  host `192.168.178.104`.
- Follow-up evidence in
  `logs/verification-runs/20260607-1708-ipad-network-identity-check/` fixed
  iPad IP reporting: the screen previously rendered USB/link-local
  `169.254.9.236`, while the real bridge host was `192.168.178.104`; the
  updated route-ranked IP selection now renders `192.168.178.104`.
- macOS passed `autoBack` + `standard1080p30` on unique automation port `4770`.
- Samsung SM-G960F and both S10e devices passed `autoBack` +
  `standard1080p30`.
- Samsung S7 edge still failed before photo save and was classified from
  collected logcat as `s7_exynos_camera_timeout`.
- iOS simulator launched with automation port `4771`, but remains launch-only
  because no camera is exposed.

Next multi-device confidence gap: run the runtime-switch matrix on physical
targets. The local proof in
`logs/verification-runs/20260607-runtime-role-switch-local-smoke-timed/`
launched macOS and the iOS simulator once in standby, switched macOS to master
and the simulator to slave in `119.533 ms`, and confirmed one connected slave.
That proves the automation path for near-instant role changes, but it is not
yet physical-device capture proof.

## Android Device Support Floor

Decision date: 2026-06-06.

HydraCam's active Android validation and distribution target starts at Android
API 24. Devices on Android 6.0/API 23 or older are deprecated for this repo and
should be treated as unsupported hardware unless a new product decision
explicitly reopens legacy-device support.

The Lenovo Phab2/PB2-690M is deprecated:

| Field | Value |
| --- | --- |
| Device | Lenovo Phab2 / Lenovo PB2-690M |
| Observed USB serial | `9d94c365` |
| OS/API | Android 6.0.1 / API 23 |
| 2026-06-06 outcome | Current HydraCam debug APK install failed with `INSTALL_FAILED_OLDER_SDK`, then the device dropped off ADB. |
| Decision | Do not build a lower-SDK Flutter variant for this device; the time and dependency/toolchain cost is not worth it. |

Context: the current debug APK built on 2026-06-06 reports `minSdk=24`.
Supporting the Lenovo would require a separate legacy Flutter/toolchain lane
before the Flutter API-24 floor plus plugin downgrades or feature removal. This
is now explicitly out of scope.

Android devices used for current validation should be API 24 or newer. The
Samsung Galaxy S7/SM-G935F on Android 8.0/API 26 remains a usable low-end
Android target after current app launch and runtime permission verification.

## Current Goals

1. Make the app reliable on Android and iOS through repeatable real-device
   smoke tests. The prior iOS physical-device white-screen blocker is closed by
   newer iPhone/iPad evidence; do not reopen it without a fresh reproducible
   failure and logs.
2. Keep release/beta distribution paths ready for TestFlight and Google Play
   internal testing, but do not claim production readiness without real device
   smoke tests.
3. Build a platform compatibility matrix across iOS, Android, macOS, Windows,
   Linux, and web as support expands.
4. Enable repeatable testing for master/slave session flow, capture, storage,
   upload, reconnect, low battery, and low storage behavior.

## Roadmap From Sheet Import

### Active Mobile Themes

- Session integrity: reconnect behavior, stale session state, joining existing
  sessions, and preventing media from crossing session boundaries.
- iOS reliability: client/server networking behavior, disconnects, navigation
  artifacts, signing/profile/release launch behavior, and regression coverage
  for the fixed iPad no-flash camera path.
- Upload and media handling: upload failure UI, cancel/requeue upload, upload
  progress/time estimates, version metadata, gallery import, and heavy video
  loading.
- Device/network awareness: show network identity, device IP/hardware/app
  version, disconnected clients, and multiple camera groups on the same LAN.
- Recording safety: critical battery autostop, storage autostop, foreground
  behavior, and synchronized time.
- Camera capture configuration: local per-device lens preference and target
  video profiles are now app settings; verify actual resolution/fps on iPhone
  12 Pro and Samsung S7/S10e before using them for production claims.
- Autograbado/unattended flow: devices start recording automatically when a
  slave connects to a master with an active session.
- Mobile authentication: restore valid Auth0 credentials on app start, persist
  refresh-capable credentials securely, end both local and browser/Auth0 sessions
  on logout, recover Android login after process death, and decide whether
  Android should use native Credential Manager/Sign in with Google for the
  account-picker experience users expect from other apps.
- Desktop/webcam support: desktop is monitoring/development-only for now; webcam
  capture is deferred by the scope decision below.
- User/player assignment: attach players/users to sessions and support mid
  session player additions.

### External Backend/Web Dependencies

- Material retrieval endpoint and slow heavy-video gallery behavior.
- Backend upload metadata fields and duration fixes.
- SignalR hub, Azure queue, delivery package, queue processors, and live
  monitoring.
- QR/user request flow for unattended court activation.
- GDPR document hosting and consent gating if implemented outside the mobile
  app.

### Future Product Ideas

These came from `SYSTEM FEATURES` and should stay roadmap-only until explicitly
pulled into active mobile work:

- AI rally segmentation, shot classification, ball/wall contact inference, heat
  maps, player body position, errors/winners location, and 3D reconstruction.
- Video referee features: live human review, AI decisioning, democratic review,
  and instant replay.
- Games and fan-facing experiences: guess-the-next-shot, referee game, loud
  calls, and score/VAR overlays.
- External refereeing/annotation APIs, user annotation, strategy suggestions,
  ball speed, step/distance counters, and padel/squash edge-case rulings.

## Recent iOS Evidence

- `logs/verification-runs/2026-06-06-iphone-personal-team-debug/`: iPhone 12
  Pro / iOS 26.4.2 debug run launched through `flutter run`, received camera
  and microphone permissions, reached master mode, created session ID `466` /
  GUID `f60e4a7a-ec8e-4897-8943-43dc0325e2d6`, captured and uploaded a photo,
  and started video recording. Limitation: this used a personal development
  team because the organization team signing state was expired for new iPhone
  debug signing.
- `logs/verification-runs/20260606-2310-ipad-capture-failure-trace-and-repro/`:
  physical iPad / iOS 15.6.1 validation passed after upgrading within the
  current camera line (`camera` 0.11.4 and `camera_avfoundation` 0.9.23+2).
  The repro captured one photo and one video, returned recording state to
  false after stop, and left a repeatable trace/repro path.
- 2026-06-07 user follow-up: manual iPad and iPhone 12 testing appears to be
  working OK.
- `logs/verification-runs/20260607-camera-settings-device-matrix/ipad-autoBack-standard1080p30/`:
  physical iPad / iOS 15.6.1 automation capture passed with local settings
  `autoBack` + `standard1080p30`, one photo, one video, and recording false
  after stop. Limitation: saved-video metadata was unavailable.
- `logs/verification-runs/20260607-camera-settings-device-matrix/iphone12-devicectl-launch-second.log`:
  iPhone 12 Pro / iOS 26.4.2 retest was blocked because the device was locked;
  SpringBoard denied launch of `com.vectorblanco.hydracam.dev`.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/ipad-autoBack-standard1080p30-after-ios-metadata/`:
  physical iPad / iOS 15.6.1 automation capture passed again with local
  settings `autoBack` + `standard1080p30`, one photo, one video, and recording
  false after stop. Limitation: saved-video metadata was still unavailable.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/iphone12-ultraWide-sport1080p60-after-fixes/`:
  iPhone 12 Pro / iOS 26.4.2 `ultraWide` + `sport1080p60` retest built and
  signed the debug app, but Flutter/Xcode timed out starting the debug session.
  A direct `devicectl` launch of `com.vectorblanco.hydracam.dev` was denied
  because the phone was locked, so the automation bridge was not discovered.
- `logs/verification-runs/20260607-new-devices-rerun/iphone12pro-ultrawide-sport1080p60/`:
  iPhone 12 Pro / iOS 26.5 passed debug automation capture with local settings
  `ultraWide` + `sport1080p60`, selected camera
  `com.apple.avfoundation.avcapturedevice.built-in_video:5`, one photo, one
  video, and recording false after stop. Limitation: saved-video metadata was
  unavailable.
- `logs/verification-runs/20260607-new-devices-rerun/iphone12pro-ultrawide-detail4k30/`:
  iPhone 12 Pro / iOS 26.5 passed debug automation capture with local settings
  `ultraWide` + `detail4k30`, the same selected 0.5x camera id, one photo, one
  video, and recording false after stop. Limitation: saved-video metadata was
  unavailable.
- `logs/verification-runs/20260607-1501-ios-icon-profile-launch/`:
  Profile build and install passed for bundle ID `com.vectorblanco.hydracam.dev`
  using personal development team `8T78Y2X37H`. A foreground no-tooling launch
  was denied because the iPhone was locked, but a no-tooling `--no-activate`
  launch succeeded and started `Runner.app/Runner` process ID `1172`. Manual
  Home Screen icon video remains pending until the iPhone is unlocked.

## Recent Android Evidence

- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_023947-s10e-autoBack-standard1080p30/`:
  Samsung S10e / Android 12 applied `autoBack` + `standard1080p30`, captured one
  photo and one video, and logged recorded video metadata as `1920x1080,
  unknown fps, 3966 ms`. Limitation: automation `end_session` left the local
  session active.
- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_023637-s10e-autoBack-sport1080p60-rerun/`:
  Samsung S10e / Android 12 applied `autoBack` + `sport1080p60`, then capture
  stalled with Samsung/Exynos camera request and buffer errors.
- `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_024916-s7-autoBack-standard1080p30/` and
  `logs/verification-runs/20260607-camera-settings-device-matrix/android/20260607_024615-s7-autoBack-sport1080p60-rerun2/`:
  Samsung S7 edge / Android 8 applied the requested settings, but both baseline
  and 60 fps runs failed before photo/video with Camera3/Exynos buffer
  timeouts.
- `logs/verification-runs/20260607-camera-settings-device-matrix/xiaomi-2201116pg-install-block/adb-install-rerun.log`:
  Xiaomi 2201116PG / Android 13 install was blocked by
  `INSTALL_FAILED_USER_RESTRICTED`.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_032251-s10e-autoBack-standard1080p30-after-batch/`:
  Samsung S10e / Android 12 applied `autoBack` + `standard1080p30`, captured one
  photo and one video, logged recorded video metadata as `1920x1080, unknown
  fps, 4014 ms`, and ended the local automation session cleanly.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607-final-s10e-autoBack-standard1080p30/20260607_035355-s10e-autoBack-standard1080p30-final-smoke/`:
  Samsung S10e / Android 12 final current-build smoke reinstalled the debug APK,
  applied `autoBack` + `standard1080p30`, captured one photo and one video,
  logged recorded video metadata as `1920x1080, unknown fps, 3866 ms`, and ended
  inactive.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033121-s10e-autoBack-sport1080p60-clean-timeout/`:
  Samsung S10e / Android 12 applied `autoBack` + `sport1080p60` and failed with
  a bounded 12 second photo-capture timeout. The earlier disposed-controller
  crash did not recur.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033406-s7-autoBack-standard1080p30-after-batch-timeout/` and
  `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/android/20260607_033527-s7-autoBack-compat720p30-after-batch-timeout/`:
  Samsung S7 edge / Android 8 applied the requested camera `0` settings, then
  failed before photo with bounded 12 second timeouts at both 1080p30 and
  720p30. Treat S7 as a baseline CameraX/device-path blocker before spending
  more time on 4K or 60 fps.
- `logs/verification-runs/20260607-camera-settings-device-matrix-rerun/xiaomi-2201116pg-install-block/adb-install-rerun.log`:
  Xiaomi 2201116PG / Android 13 install retry remains blocked by
  `INSTALL_FAILED_USER_RESTRICTED`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_144440-new-rf8m21j8xrt-standard1080p30/`:
  newly connected Samsung S10e / Android 12 (`RF8M21J8XRT`) applied
  `autoBack` + `standard1080p30`, captured one photo and one video, ended the
  automation session, and logged recorded video metadata as `1920x1080,
  unknown fps, 3966 ms`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_144222-new-g960f-standard1080p30/` and
  `logs/verification-runs/20260607-new-devices-rerun/20260607_144932-new-g960f-compat720p30/`:
  newly connected Samsung SM-G960F / Android 10 applied camera `0` settings and
  initialized the camera, but both 1080p30 and 720p30 failed before photo save
  with CameraX `ImageCaptureException: Not bound to a valid Camera`.
- `logs/verification-runs/20260607-new-devices-rerun/20260607_145107-s7-edge-datasaver480p30-rerun/`:
  Samsung S7 edge / Android 8 applied `autoBack` + `dataSaver480p30`, selected
  camera `0`, initialized, then timed out after 12 seconds before photo save.
  Logcat shows repeated ExynosCamera3 wait timeouts plus Camera2 reopen /
  `ERROR_MAX_CAMERAS_IN_USE` errors.

## Release Blockers

- iOS production submission still needs a foreground signed release/profile
  smoke run on target hardware, using the intended Apple team/certificates. The
  2026-06-07 Profile dev build installs and launches as a background process
  without Flutter tooling, but foreground icon proof is still pending because
  the iPhone was locked during activation.
- Store privacy answers must be reviewed against current code and backend
  behavior before submission.
- Android and iOS real-device smoke tests must pass on the exact release lane.
- Camera lens/profile claims still need production-grade proof. iPhone 12 Pro
  ultra-wide 1080p60 and 4K30 now pass in debug automation, but iOS saved-video
  metadata remains unavailable and release/profile launch proof is still needed.
  Samsung S7 rear-wide 1080p60/4K30 remains unproven because the device fails
  before photo save even at `dataSaver480p30`.
- Human-user login must survive app restart and Android process-death during
  browser authentication, and logout/account switching must be validated before
  release claims depend on user identity.
- A two-device HydraCam flow must pass on the same local network or hotspot:
  discovery, slave connection, photo capture, video start/stop, local save,
  upload queue, and session end.
- Do not spend release-blocker time on Android 6.0/API 23 or older hardware.
  The Lenovo Phab2/PB2-690M path is deprecated and should not reopen unless a
  product owner explicitly reverses the support floor decision.
- Docs and Linear issues must not imply backend/Azure work is complete unless it
  has current proof outside this mobile repo.

## Desktop/Webcam Scope Decision

Decision date: 2026-06-06.

This completes the imported backlog decision task for `JAVI IMMEDIATE BACKLOG`
rows 76, 83, and 103.

| Platform | Current scope | Capture support |
| --- | --- | --- |
| Android | Primary mobile target for master/slave capture and validation. | In scope. |
| iOS | Primary mobile target; recent iPhone 12 Pro and physical iPad evidence shows launch/capture works in debug/test flows. | In scope. |
| macOS/Windows/Linux | Development, diagnostics, monitoring, and possible viewer/control workflows only. | Deferred. |
| Web | Future viewer/control or portal surface only. | Deferred. |

Desktop/webcam capture is not an active implementation target in this mobile
repo. Reopening that scope would require a separate design for camera APIs,
file/gallery persistence, permission behavior, packaging, and cross-platform
test coverage. Until then, do not create Linear issues for generic "use webcam"
or "Windows version" rows unless a concrete non-capture monitoring/control
workflow is requested.

2026-06-07 update: macOS native controller support is now enabled for debug
builds without implementing desktop webcam capture. The app skips unsupported
`permission_handler` startup calls on macOS, defaults local master recording off
on macOS unless the user explicitly enables it, signs debug/release macOS
targets with local-network/media/location entitlements, and uses a mock local
camera path so controller flows can run while real desktop capture remains
deferred.
