# Evidence Run: iPad legacy upload success response

- Source: user request 2026-06-17
- Slug: `ipad-legacy-upload-success-response`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Current iPad build accepts legacy plaintext upload success and marks video uploaded

## Device Matrix

- iPad (5), iOS 17.7.11, automation target
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice
  `0A947DBD-A462-5BAA-AB84-17F143D41619`, role `master-upload`.

## Evidence

- Current checkout Profile build installed and launched through the one-device
  matrix runner at `current-build-ipad-single-capture/`; the runner passed one
  iPad photo/video capture but ended the session before the video upload drained.
- Manual bridge session `492` / GUID
  `d034de8b-8757-4ffc-92a4-423f196fdea1` recorded
  `REC_3A1472AD-4EE5-4378-910D-3C42D3E20AD8.mp4`, waited for upload drain, and
  `/session` reported `isUploading=false`, `queueLength=0`.
- `device-logs/ipad-logs-after-session-492-video-upload.json` shows
  `Media uploaded successfully` and `Media uploaded: ...REC_3A1472AD...mp4`
  for the manual video, with no new malformed-response or failed-upload entry
  for session `492`.
- `device-logs/hydracam-session-492-details.html` shows the legacy portal video
  row and blob URL for session `492`.
- `screenshots/ipad-video-upload-after-success.png` and
  `video/ipad-session-492-uploaded-video.mp4` were copied from the physical iPad
  app data container.

## Result

- Final disposition: passed
