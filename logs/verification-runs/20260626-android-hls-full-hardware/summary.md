# Android HLS full support — record / play / upload (hardware proof)

**Date:** 2026-06-26
**Branch:** `feature/android-hls-full` (worktree `.worktrees/android-hls-full`)
**Device:** Samsung SM-G970F (Galaxy S10e), Android 12 / API 31, serial `RF8M21J8XRT`
**Backend:** local media-timeline stack (backend 3001, file-server 3102, frontend 5173) — already running.

Closes the open item in `docs/control/fixed-camera-hls-implementation-plan.md`
Task 8: "prove runtime Camera2 output on Android emulator/hardware before
claiming production readiness."

## Result: PASS on all four goals

### 1. RECORD — real Camera2 HLS on hardware
- Found and fixed a real crash: when the camera fails to open, the session was
  released while the `HydraCamFixedCameraVideoDrain` thread was still calling
  `MediaCodec.dequeueOutputBuffer`, throwing an uncaught `IllegalStateException`
  that **crashed the whole app** (`FixedCameraCamera2HlsRecorder.kt`). The drain
  and audio loops are now abortable and swallow teardown `IllegalStateException`;
  `release()` joins them before releasing codecs.
  - Before fix: app FATAL crash on first camera-open failure
    (`camera2-evidence-run.log`, `run3-logcat.txt`).
  - After fix: 20 clean retries, no crash (`camera2-flutter-run-proof.log`).
- Camera open requires the app to be **foreground + unlocked**: `flutter test`
  integration mode and a locked screen both report the app as background
  (`CAMERA_DISABLED … proc state 20`, `isUidActiveLocked … isActive false`).
  With the S10e unlocked and screen kept on, Camera2 opened.
- Real recording finalized: `CAMERA2_PROOF_FINALIZED state=finalized chunks=2
  duration=3.599s` (`camera2-flutter-run-proof3.log`).
- Bundle pulled via `run-as` (`camera2-hardware-bundle/`):
  `playlist.m3u8` (HLS v7, fMP4) + `init.mp4` + 2 `.m4s` (1.3 MB + 192 KB).
- **ffprobe validates a real playable HLS:** `format=hls`, `h264 1280x720`,
  ~30 fps, `duration=3.599` (raw decode also confirmed via Android
  `MediaMetadataRetriever`: width=1280 height=720).

### 2. PLAY — in-app HLS playback on-device
- New `LocalHlsServer` (`lib/services/local_hls_server.dart`) serves the bundle
  over loopback; `HlsPlayerView` (`lib/widgets/hls_player_view.dart`) plays it
  with `video_player`/ExoPlayer.
- Fixed: ExoPlayer (native) is blocked from `http://127.0.0.1` by the API 28+
  cleartext default → added a loopback-only network-security-config
  (`android/app/src/main/res/xml/network_security_config.xml`). Dart networking
  is unaffected.
- On-device proof (`hls-player-proof2.log`):
  `HLS_PLAYER_PROOF_STATE initialized=true size=1280.0x720.0 duration=3599ms
  position=1922ms isPlaying=true hasError=false` → `HLS_PLAYER_PROOF_OK`.
- Visual: `in-app-player-screenshot.png` shows the real camera2 frame playing
  inside HydraCam.

### 3 & 4. UPLOAD + backend playback
- Real camera2 bundle uploaded to the running backend via the app's
  queue/bridge (`camera2-real-upload.txt`): event
  `hydracam-hydracam-20260626-android-hls-full-camera2`, playlist registered as
  the event video.
- Backend serves the event-scoped rewritten playlist (segment URIs → File
  Registry stream URLs); **ffprobe plays it end-to-end over HTTP**:
  `format=hls h264 1280x720 duration=3.599`
  (`camera2-real-playback-playlist.m3u8`, `camera2-real-playback-ffprobe.txt`).
- A separate ffmpeg fMP4 fixture upload/playback was also proven
  (`fixture-upload.txt`, `fixture-playback-ffprobe.txt`).

## Static / unit validation
- `flutter analyze`: No issues found (whole project).
- `flutter test`: full suite green (after centralizing player error color in
  AppTheme). New host tests: `local_hls_server_test.dart` (5),
  `hls_player_view_test.dart` (2).
- Android `:app:testDebugUnitTest`: BUILD SUCCESSFUL (JDK 17).

## Reproduce
- Camera2 hardware record (device unlocked, screen on):
  `flutter run -t tool/camera2_hls_proof_main.dart -d RF8M21J8XRT`
- In-app playback of the latest bundle:
  `flutter run -t tool/hls_player_proof_main.dart -d RF8M21J8XRT`
- Pull bundle: `adb exec-out run-as com.amaia23.hydracam cat <ext path>`
- Upload: `dart run scripts/upload_hls_bundle.dart --directory <dir>
  --session-guid <guid> --device-id fixed-court-a --recording-id <id>`

## Known constraint
Camera2 capture requires the device foreground + unlocked (Android camera
policy). `flutter test` integration mode cannot satisfy this on this Samsung, so
hardware capture is proven via a foreground `flutter run` entrypoint.
