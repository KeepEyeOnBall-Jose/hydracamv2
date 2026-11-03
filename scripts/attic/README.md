# scripts/attic/

Quarantine for unreferenced one-off scripts, moved here 2026-08-26 during the
scripts/ tooling audit. Each file was verified to have zero references from
`AGENTS.md`, runbooks, `README`, `docs/`, `.github/`, `scripts/`, and
`automation_scenarios/` — nothing in the live tooling calls, imports, or
documents these as a supported entry point.

These scripts are kept for reference only:

- Not maintained — no expectation they still run against current device
  images, backend endpoints, or file layouts.
- Excluded from quality gates — `.github/workflows/scripts-quality.yml`'s
  shellcheck glob (`scripts/*.sh`) and the `scripts/test_*.py` runner are
  both non-recursive, so nothing in this directory is linted or executed
  by CI.
- Safe to delete after 2026-12 if still unused. If you need one of these
  again before then, promote it back to `scripts/` and give it a real
  reference (AGENTS.md, a runbook, or a caller) so it doesn't drift back
  into the attic.

## Contents

- `android_emulator_inventory.py` — dumps `adb`/emulator inventory to
  `logs/android_emulator_inventory.json` for one-off inspection.
- `check_android_sdk_state.py` — snapshots local Android SDK/AVD filesystem
  state to `logs/android_sdk_state.json`.
- `check_device_status.py` — polls hardcoded `127.0.0.1:59xx/session`
  endpoints on three local emulators to check automation-bridge status.
- `discover_automation_bridge.py` — scans a subnet for a HydraCam
  automation bridge without issuing capture commands.
- `download_portal.py` — scrapes session/detail pages directly from the
  HydraCam web portal (no backend API) for a one-time portal investigation.
- `portal_scraper.py` — parses a saved portal HTML page (from
  `download_portal.py`) to extract session links and media asset URLs.
- `download_small_videos.sh` — wrapper that calls
  `download_oldest_videos.py` to fetch only videos under 500MB.
- `dump_sessions.sh` — dumps a device's `files/sessions` directory listing
  and metadata via `run-as` to a text file.
- `enumerate_sessions.py` — enumerates session directories on Android
  devices over `adb` and extracts metadata.
- `fix_xcode_sandbox.sh` — patches `ios/Runner.xcodeproj/project.pbxproj`
  to work around an Xcode build-sandbox issue.
- `ios_build_with_user_ruby.zsh` — builds iOS using the developer's local
  Homebrew Ruby/gems instead of system Ruby.
- `list_device_videos.py` — lists videos on a connected Android device
  sorted by date.
- `monitor_download.sh` — polls a hardcoded `~/Desktop/android_videos`
  folder to report download progress.
- `pull_and_clean_videos.sh` — pulls recent camera videos from a connected
  device to the desktop, then deletes the originals from the device.
- `pull_session_media.sh` — pulls media for one hardcoded session GUID off
  a specific emulator into `automation_runs/`.
- `recreate_avds.sh` — recreates the project's Android Virtual Devices on
  a fresh machine via `sdkmanager`/`avdmanager`.
- `search_stop_logs.py` — greps a specific hardcoded automation-run
  `logs.json` for stop/save/upload keywords.
- `search_video_logs.py` — greps the same kind of hardcoded run log for
  video-related events.
- `start_ftp_server.py` — starts a temporary local FTP server (via
  `pyftpdlib`) to receive files pushed from an Android device.
- `upload_videos_ftp.py` — finds videos on a device and uploads them to
  the Mac via FTP using `curl`.
