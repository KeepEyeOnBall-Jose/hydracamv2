# Evidence Run: Samsung S7 higher-resolution compatibility mode

- Source: docs/control/status-and-roadmap.md
- Slug: `s7-higher-resolution-compat`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] The S7 compatibility policy preserves standard1080p30 resolution instead of forcing 480p.
- [x] The current automation-enabled APK installs on the Samsung S7 edge.
- [x] A direct S7 automation-master photo/video probe at standard1080p30 succeeds or records the exact higher-resolution blocker with logs.
- [x] If capture succeeds, copied JPEG/MP4 artifacts show the achieved resolution.

## Device Matrix

- Samsung S7 edge SM-G935F, Android 8.0/API 26, serial
  `9885e6503930304946`, direct automation-master camera compatibility target.

## Evidence

- Current automation-enabled APK built and installed on the S7 with
  `HYDRACAM_AUTOMATION=true` and automation bridge port `4762`.
- Automation bridge accepted `standard1080p30` settings and reported
  `videoCaptureTarget: 1080p at 30 fps`.
- Device logs in `device-logs/s7-after-1080-settings.json` show the SM-G935F
  compatibility policy preserving the requested resolution while using
  platform-default FPS.
- Device logs in `device-logs/s7-after-1080-photo-video.json` show
  `session_null/CAP3852750848982854487.jpg` and
  `session_null/REC5731514365530415283.mp4` saved from direct automation
  commands.
- Copied artifacts:
  `screenshots/s7-standard1080p30-photo.jpg` and
  `video/s7-standard1080p30-video.mp4`.
- `file` reports the copied JPEG as `SM-G935F` EXIF at 1920x1080.
- `ffprobe` reports the copied MP4 video stream as 1920x1080, duration
  `13.962844` seconds.

## Result

- Final disposition: passed. The S7 compatibility fix no longer forces 480p;
  it preserves `standard1080p30` and only avoids explicit FPS on SM-G935F. This
  run intentionally bypassed backend session creation, so the earlier
  `start_session` timeout remains a separate session/backend automation issue.
