# Fixed-Camera HLS Implementation Plan

Last reviewed: 2026-06-26 (content dated 2026-06-26).

**Goal:** Add a fixed-camera HLS path that can be exercised from real Android cameras later and from local squash HLS example bundles now.

**Architecture:** Keep the existing MP4/JPEG capture and upload path intact. Add an HLS stream-manifest lane that uploads or registers `init.mp4`, `playlist.m3u8`, and `.m4s` chunks, then links the playlist as the event video asset in media-timeline with HLS metadata that points to the part file IDs.

**First slice:** Implement camera-free local HLS upload examples. HydraCam builds a manifest from a local HLS bundle and posts it to media-timeline. Media-timeline stores all HLS files through the File Registry and records the playlist as the canonical event media row.

**Current proof:** `logs/verification-runs/20260619-local-fixed-camera-hls-upload/` contains a synthetic squash HLS bundle and a successful local upload output. The media-timeline bridge stored the playlist as the session video, stored init/chunk file IDs in `event_assets.metadata_blob`, and resolved the playlist through File Registry. `logs/verification-runs/20260619-live-hls-idempotency-proof/` proves the same HydraCam local HLS fixture can be uploaded twice against the Service Monitor-managed backend with the same `sessionGuid + deviceId + recordingId`, returning the same playlist file ID and leaving the event at one video. `logs/verification-runs/20260619-live-hls-playback-proof/` contains a valid fMP4 HLS fixture generated locally with `ffmpeg`; after the bridge switched to recording-scoped File Registry upload names, the fresh event `hydracam-20260619-live-hls-playback-proof-v2` returned unique playlist/init/chunk IDs and rendered in the local media-timeline frontend video detail page at `640x360` with `readyState: 4` and duration `4.023219`. The upload contract now also accepts optional `nativeTimingMetadataJson` for Przemek-style sync confidence, NTP, and camera timing metadata. When `recordingId` is supplied, media-timeline treats `sessionGuid + deviceId + recordingId` as the finalized HLS upload identity and returns the existing playlist stream for duplicate uploads. HydraCam also has a Flutter/Android fixed-camera HLS capability and recording contract; Android currently reports the channel as available, exposes an app-owned fixed-camera HLS output directory, defaults to `recorderMode: synthetic_local`, and advertises `supportedRecorderModes: ["synthetic_local", "camera2_hls"]`. Android `startRecording` / `stopRecording` generate a finalized local HLS bundle without camera hardware when no `cameraId` is supplied, including `playlist.m3u8`, `init.mp4`, `.m4s` chunks, duration fields, and synthetic `nativeTimingMetadataJson`. When a `cameraId` is supplied, the channel routes to a first Camera2/MediaCodec/AudioRecord HLS recorder adapter that buffers encoded samples and finalizes the same bundle shape on stop. Android now also has tested native HLS playlist/chunk naming, fMP4 init segment, H.264 SPS/PPS-to-`avcC` conversion, Annex B sample conversion, encoded-sample HLS finalization, and fMP4 media fragment writers for the recorder output path. The Camera2 adapter now has real-hardware runtime proof: run `logs/verification-runs/20260626-android-hls-full-hardware/` recorded a finalized `camera2_hls` bundle on a physical Samsung S10e (SM-G970F, Android 12 / API 31) at `1280x720@30`, validated as a playable HLS stream by `ffprobe` (`format=hls`, `h264 1280x720`, `duration=3.599`) and decoded by Android `MediaMetadataRetriever`, then uploaded through the queue/bridge to the running media-timeline backend and played back end-to-end over HTTP from the event-scoped rewritten playlist. That run also fixed a real crash in `FixedCameraCamera2HlsRecorder`: when the camera failed to open, the session was released while the video-drain thread was still calling `MediaCodec.dequeueOutputBuffer`, raising an uncaught `IllegalStateException` that crashed the app; the drain/audio loops are now abortable and joined before the codecs are released. Camera2 capture requires the app to be foreground with the device unlocked (Android `CAMERA_DISABLED`/`isUidActive` policy), so hardware capture is proven through a foreground `flutter run` entrypoint (`tool/camera2_hls_proof_main.dart`) rather than `flutter test` integration mode. Finalized HLS bundle uploads now have bounded retry through `HlsStreamUploadQueue`; finalized native recording results can be converted to uploadable bundles and enqueued with raw native timing JSON preserved. The local squash-bundle upload script uses that queue and can pass `--native-timing-metadata-json` into the media-timeline bridge. HydraCam can also replay a finalized bundle in-app on Android: `LocalHlsServer` (`lib/services/local_hls_server.dart`) serves the bundle over loopback and `HlsPlayerView` (`lib/widgets/hls_player_view.dart`) plays it with `video_player`/ExoPlayer (size `1280x720`, actively playing in the same run); a loopback-only network-security-config (`android/app/src/main/res/xml/network_security_config.xml`) allows ExoPlayer's native HTTP to reach `127.0.0.1`. The `FixedCameraHlsScreen` (`lib/screens/fixed_camera_hls_screen.dart`, reachable from the app-bar menu) ties record → in-app replay → upload together. `getCapabilities` now also returns `cameraModes`: every camera output size the device exposes, intersected with the H.264 encoder's `VideoCapabilities` so only encoder-recordable sizes (with per-size max fps) are advertised; the screen lets the user pick any mode and defaults to the highest, and the recorder accepts any size rather than a hardcoded resolution. The same `20260626-android-hls-full-hardware` run proved a high-resolution audio capture on the S10e at the device's top recordable mode `4032x2268 @30fps` with an AAC audio track (ffprobe `format=hls`, `h264 4032x2268` + `aac 48000 Hz mono`, `duration=9.929`), uploaded and played back end-to-end through media-timeline.

## Cross-Repo Tasks

1. Add media-timeline bridge support for multipart HLS bundles:
   - `POST /api/hydracam-bridge/compat/sessions/upload-hls`
   - accept one playlist, optional init segment, and one or more chunks
   - upload all files to File Registry as video-associated assets
   - link the playlist file ID through the existing HydraCam bridge media mapping
   - persist HLS metadata on the event asset and mirror asset
   - expose event-scoped playback playlists that rewrite `init.mp4` and `.m4s` URIs to File Registry stream URLs

2. Add HydraCam local HLS bundle support:
   - model a local HLS bundle manifest
   - parse a directory containing `playlist.m3u8`, optional init segment, and `.m4s` chunks
   - upload the bundle with session/device/capture metadata to media-timeline
   - send a stable `recordingId` for completed recordings so retries are idempotent

3. Add example/test lane:
   - use small synthetic squash-named HLS segment files for unit tests
   - use a valid local fMP4 HLS fixture for browser playback proof
   - keep real Android Camera2/HLS implementation as the next slice after the bridge contract is green

4. Add native capability boundary:
   - expose `hydracamv2/fixed_camera_hls` from Android
   - parse it through `FixedCameraHlsRecorderService` in Flutter
   - define the Dart `startRecording` / `stopRecording` request and result contract
   - expose `nativeRecorderImplemented`, `cameraRecorderImplemented`, `recorderMode`, and `supportedRecorderModes` so synthetic-local recording is distinguishable from real Camera2 capture

5. Add Android synthetic-local recorder path:
   - add `FixedCameraLocalHlsRecorder` for camera-free start/stop lifecycle proof
   - generate `init.mp4`, two `.m4s` chunks, `playlist.m3u8`, duration fields, and synthetic timing metadata through the same native writer path the Camera2 recorder will use
   - wire Android `startRecording` / `stopRecording` to return finalized bundle paths instead of `native_recorder_not_implemented`

6. Add Android-native HLS writer components:
   - add `FixedCameraHlsPlaylistWriter` for playlist rendering and eight-digit chunk naming
   - add `FixedCameraMp4InitSegmentWriter` for `init.mp4` `ftyp`/`moov` output with video/audio track defaults
   - add `FixedCameraH264AvcConfig` to convert MediaCodec SPS/PPS config buffers into `avcC`
   - add `FixedCameraH264SampleFormatter` to convert Annex B encoded media samples to length-prefixed MP4 samples
   - add `FixedCameraEncodedHlsWriter` to finalize encoded H.264/AAC samples into init/fragment/playlist bundles
   - add `FixedCameraMp4FragmentWriter` for `.m4s` `styp`/`moof`/`mdat` output from encoded H.264/AAC samples
   - cover native writer behavior with `:app:testDebugUnitTest`
   - use the native writers from the recorder output path once Camera2/MediaCodec capture is attached

7. Add finalized HLS upload retry:
   - queue completed HLS bundles with bounded retry attempts
   - convert finalized native recording results into queue entries with playlist/init/chunk paths and raw native timing metadata preserved
   - reuse the queue from the local synthetic squash-bundle upload script
   - let the local upload script send `--native-timing-metadata-json` for squash-bundle metadata proofs
   - rely on media-timeline's finalized upload idempotency for duplicate `recordingId` retries
   - keep live incremental part upload as a separate product decision

8. Add first Camera2 HLS recorder adapter:
   - keep synthetic-local recording as the default when no `cameraId` is supplied
   - route explicit `cameraId` requests to Camera2, H.264 `MediaCodec`, optional AAC `AudioRecord`, and `FixedCameraEncodedHlsWriter`
   - compile and unit-test the formatter/finalizer boundary
   - prove runtime Camera2 output on Android emulator/hardware before claiming production readiness

9. Verification gates:
   - media-timeline focused Vitest tests for bridge service/router
   - HydraCam focused Flutter tests for HLS manifest and upload client
   - Android unit tests for native HLS writer components
   - then `flutter analyze` and the narrow backend test command
   - emulator/macOS app validation only after the contract layer is passing
