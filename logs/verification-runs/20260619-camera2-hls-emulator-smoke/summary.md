# Camera2 HLS Emulator Smoke

Date: 2026-06-19

Scope:
- Fixed-camera Android HLS channel.
- Synthetic local HLS mode.
- Camera2/MediaCodec HLS mode with `includeAudio:false`.

Evidence:
- `flutter test -d emulator-5554 --no-uninstall integration_test/fixed_camera_hls_channel_test.dart` passed both integration tests.
- `ffprobe` accepted `camera2-hls-final/playlist.m3u8` as H264 video, 640x480, duration about 2.08 seconds.
- Final pulled artifacts live under `camera2-hls-final/` and `synthetic-local-final/`.

Notes:
- The no-audio Camera2 init segment omits the AAC track, which fixed the prior `ffprobe` AAC parser failure.
- The synthetic fixture uses tiny generated media payloads and may emit decoder warnings; it is retained as a channel/file-contract smoke, not playback-quality proof.
