# Evidence Run: Recording, upload queue, and session regression coverage

- Source: docs/control/architecture-and-testing.md#test-strategy
- Slug: `przemek-server-client-emulator-e2e`
- Verification tier: B (emulator-simulator-e2e)
- Status: passed

## Acceptance Checks

- [x] Latest Alicia Web session features merge without losing local Docker and event automation
- [x] The complete Alicia Web test suite and local Compose smoke pass
- [x] The Przemek Android client records and uploads a finalized playable HLS stream through the merged server

## Device Matrix

- `Hydra_Master_API34`, Android 14 (API 34), `emulator-5554`,
  HydraCam client. Device ID: `794d0477730abc7c`.

## Evidence

- `commands.log`: server merge, 108-test suite, persistent and fresh-database
  Compose smokes, and three complete emulator E2E runs.
- `screenshots/emulator-5554-final.png`: connected client after final playlist
  upload with zero chunks pending.
- `video/emulator-5554-final.mp4`: final connected-state UI recording.
- `device-logs/emulator-5554-final-logcat.txt` and
  `device-logs/alicia-web-compose.log`: client and backend runtime logs.
- `device-logs/stream-39f3425846de43169bc227701c1e8c2c-ffprobe.json`:
  playable H.264/AAC, 1280x720, 30 fps, 8.67-second finalized HLS proof.
- `screenshots/failed-health-state.png` and the paired failure log preserve the
  pre-fix `recording_sessions` migration regression.

## Result

- Final disposition: passed.
- Alicia Web merge: `8b93f33`; persistent-database migration fix: `d755b32`;
  fresh-seed compatibility fix: `22a1e48`.
- The final E2E event was ID 27. Stream
  `39f3425846de43169bc227701c1e8c2c` finalized with five chunks.
