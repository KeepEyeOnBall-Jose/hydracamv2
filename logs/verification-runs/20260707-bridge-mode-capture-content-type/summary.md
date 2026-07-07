# Bridge Mode Capture Content-Type Rerun

- Status: partial
- Device: `RF8M21J8XRT` Samsung S10e
- Command:
  `python3 scripts/run_android_capture_profile.py --serial RF8M21J8XRT --build --manifest automation_scenarios/quad_smoke_extended.json --scenario bridge-mode-quad-smoke-s10e-content-type --output-dir logs/verification-runs/20260707-bridge-mode-capture-content-type --dart-define HYDRACAM_USE_MEDIA_TIMELINE_BRIDGE=true --dart-define HYDRACAM_MEDIA_TIMELINE_API_BASE_URL=http://192.168.178.173:3001/api`
- Run directory:
  `logs/verification-runs/20260707-bridge-mode-capture-content-type/20260707_151322-bridge-mode-quad-smoke-s10e-content-type/`
- Bridge session GUID: `c91ee2de-8cf3-4c50-ab7d-8506aa907e77`
- Media-timeline status after timeout:
  `bridge-uploaded`, `photos=1`, `videos=0`, `total=1`
- Remaining issue:
  the video upload and session-end call hit `Connection refused` after the media-timeline backend restarted during the run. This is no longer the original `application/octet-stream` rejection; the photo upload succeeded after the explicit multipart content type fix.
- Non-blocking device warnings:
  Android permission grant warnings for storage/media-location and gallery save directory warnings remained present, matching prior hardware smoke behavior.
