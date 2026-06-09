# Evidence Run: Verify iPad uploader failure against webservice state

- Source: docs/control/status-and-roadmap.md#current-mobile-status
- Slug: `ipad-uploader-webservice-check`
- Verification tier: A (real-hardware)
- Status: failed

## Acceptance Checks

- [x] Live iPad automation bridge reports the running session identity and upload state
- [x] Persisted iPad app logs show the upload request outcome or an actionable missing-log blocker
- [x] HydraCam webservice is checked for the same session GUID or exact endpoint blocker

## Device Matrix

- iPad (5), iOS 17.7.11 21H461, Flutter device
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice
  `0A947DBD-A462-5BAA-AB84-17F143D41619`, running HydraCam Profile automation
  bridge on `169.254.193.202:4762`. The same bridge also answered at
  `192.168.178.104:4762` with the expected automation target id.

## Evidence

- `commands.log`: device inventory, iPad bridge `/settings`, `/session`,
  `/logs`, authenticated webservice probe, screenshot capture, and app-container
  copy commands.
- `screenshots/ipad-uploader-failed-state.png`: current iPad app screenshot
  captured through the automation bridge.
- `device-logs/ipad-session-local-screenshot-boundary-proof-metadata.json`:
  copied active-session metadata. It shows session GUID
  `local-screenshot-boundary-proof`, one photo and two videos, all with
  `isUploaded: false`.
- `video/ipad-failed-upload-sample.mp4`: copied sample media file from the same
  iPad session; this is one of the media items that remained not uploaded.
- `device-logs/webservice_probe.mjs`: sanitized probe helper. It reads the app's
  configured M2M settings but prints only HTTP status and response bodies.

## Result

- Final disposition: verified failed upload state.
- Live iPad session snapshot:
  `{"sessionGuid":"local-screenshot-boundary-proof","deviceType":"Master","isActive":true,"photoCount":1,"videoCount":2,"queueLength":0,"isUploading":false,"isRecording":false}`.
- iPad persisted logs show manual upload started with queue length 3 under
  `sessionGuid=local-screenshot-boundary-proof`, M2M token acquisition succeeded,
  and each media upload returned `404 - Session not found.`
- Authenticated webservice double-check against
  `https://hydracam.azurewebsites.net/api/sessions/upload-media?sessionGuid=local-screenshot-boundary-proof&isPhoto=true`
  also returned HTTP 404 with body `Session not found.`
- The likely cause is not iPad networking or Auth0. The running iPad session is
  an automation/local session (`start_local_session`) that never created a
  backend HydraCam session, so upload is correctly rejected by the webservice.
