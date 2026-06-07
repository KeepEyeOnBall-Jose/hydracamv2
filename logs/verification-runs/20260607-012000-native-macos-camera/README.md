# Native macOS Camera Verification

Run timestamp: 2026-06-07 01:20-01:29 CEST

## Summary

- `camera_desktop` enumerated two real macOS cameras with `isUsingMockCamera=false`:
  - FaceTime HD Camera
  - José Ramón’s iPhone Camera
- Forced-master automation captured real local media under session GUID
  `native-macos-camera-20260607-012000`.
- Forced-slave automation connected to a local fake WebSocket master and captured real local
  media under session GUID `native-macos-camera-slave-video-20260607-012000`.
- Auto-upload was disabled, so media remained queued locally for both master and slave proof runs.

## Key Evidence Files

- `commands.log`: command transcript for build, launch, enumeration, master capture, and slave capture.
- `master-list-cameras.json`: app-level camera enumeration through `camera_desktop`.
- `master-session-after-capture.json`: master session snapshot after photo and video capture.
- `session-artifacts.txt`: master media file sizes and metadata.
- `slave-session-artifacts.txt`: slave media file sizes and metadata.
- `device-logs/automation-master-capture-logs.json`: master app logs.
- `device-logs/automation-slave-long-capture-logs.json`: slave app logs.
- `device-logs/fake-master-long.log`: fake master WebSocket command transcript for the slave proof.

## Notes

- The first slave attempt discovered a live LAN master at `192.168.178.64`; that proved native slave
  discovery/connection, but master-only automation commands were unavailable because the app was in
  slave UI. The final slave proof forced the app to `HYDRACAM_AUTOMATION_ROLE=slave` with
  `HYDRACAM_AUTOMATION_MASTER_IP=127.0.0.1`.
- The slave app reconnected to the live LAN master after the fake master closed. The media proof is
  still under the intended local fake-master session directory before that reconnect.
