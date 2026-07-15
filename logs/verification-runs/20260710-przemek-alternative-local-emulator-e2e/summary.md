# Przemek Alternative Local Emulator E2E

Date: 2026-07-10

## Source provenance

- Alicia Web worktree: `/Users/jose/src/work/hydracamv2/.worktrees/przemek-alicia-web-20260710`
- Alicia Web branch: `codex/przemek-local-events-20260710`
- Alicia Web commits: `fca5807`, `b1ce5bc`
- Android worktree: `/Users/jose/src/work/hydracamv2/.worktrees/przemek-hydracam-client-20260710`
- Android branch: `codex/przemek-local-emulator-20260710`
- Android commits: `8c5520f`, `cd5653e`
- Both source worktrees were clean after the run. The dirty reference checkouts were not modified.

## Runtime

- Compose project: `przemek-alicia-web-20260710`
- API: host `127.0.0.1:15050`, emulator `10.0.2.2:15050`
- MQTT: host/emulator `11883`, container `1883`
- Emulator: `emulator-5554`, `Hydra_Master_API34`, Android API 34
- App package/activity: `com.alicia.hydracamclient/.MainActivity`
- App-scoped Android ID: `794d0477730abc7c`

## One-command proof

`scripts/local-system-e2e.sh emulator-5554 Hydra_Master_API34` reused the healthy isolated backend and emulator, then ran tests, built, installed, deployed debug config, registered the app-scoped device ID, cold-launched the app, checked the UI, created a new event, toggled recording through Alicia Web/MQTT, finalized HLS, uploaded all artifacts, and verified the backend stream.

## Verified results

- Android debug unit/build gate: passed.
- Debug/release merged-manifest boundary: passed; cleartext and the DUMP-protected automation receiver are debug-only.
- Alicia Web container suite: 87/87 passed, including concurrent event idempotency and persisted-DB migration.
- Fresh installed-app event: ID `13`, type `automation-fresh-event`, exact authenticated read-back passed.
- Recording stream: `b774fc2d2515463ba88aec88cc693622`.
- Media: five `.m4s` chunks, non-empty `init.mp4`, final playlist with `#EXT-X-ENDLIST`.
- HTTP playback playlist: status 200.
- `ffprobe`: HLS, H.264 1280x720, AAC 48 kHz mono, duration 8.914 seconds.
- UI: `Saved ...`, `Recording mode: 1280x720@30fps`, `Chunks left for upload: 0`, and `Uploaded final playlist`.
- Android crash buffer: empty.

## Evidence files

- `local-system-e2e.txt`: complete one-command run output.
- `event-13.json`: authenticated event read-back.
- `ffprobe.json` and `playlist.m3u8`: uploaded HTTP media validation.
- `stream-files.txt`: backend artifact inventory.
- `emulator-final.png`, `ui.xml`, `ui-summary.txt`: foreground visual/UI proof.
- `compose-ps.txt`, `backend-runtime.log`: exact backend runtime and request evidence.
- `device-inventory.txt`, `window-focus.txt`, `logcat.txt`, `crash-log.txt`: device/process/runtime evidence.

## Separate release-lane item

The upstream Android project still targets API 30, so `assembleRelease` lint reports the existing `ExpiredTargetSdkVersion` issue. This does not affect the verified debug/local-emulator path and should be handled as a separate release upgrade.
