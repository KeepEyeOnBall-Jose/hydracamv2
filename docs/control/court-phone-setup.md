# Court Phone Setup and K2 Enrollment

Last reviewed: 2026-11-21 (content dated 2026-11-21).

This document defines the canonical host and phone-side bring-up tooling for
Samsung Android court phones in `hydracamv2`, aligned with K2 Court Cloud
contract **C1 `1.29`** and its single device record model.

## Overview and Files

| Component | Path | Responsibility |
| --- | --- | --- |
| Full phone setup CLI | `scripts/court_phone_setup.py` | Resumable step runner from stock Samsung to rooted, hardened, K2-enrolled court device |
| K2 enrollment CLI | `scripts/court_k2_enroll.py` | Single-device K2 registration, alias upsert, credential cache, and phone receiver push/clear |
| Hardware profiles | `scripts/hydracam_lib/court_profiles.py` | Model metadata, firmware list, button sequences, flash partitions, root/charge/Wi-Fi modes |
| K2 contract & client | `scripts/hydracam_lib/court_k2.py` | C1 `1.29` version/skew checks, URL validation, no-redirect `/device/v1/token`, idempotent registration |
| State & lock engine | `scripts/hydracam_lib/court_enroll_engine.py` | Atomic `0o600` step state (redacts secrets), PID locks, daily reboot budget, human prompt helper |
| ADB / device helpers | `scripts/hydracam_lib/court_phone_device.py` | Heimdall/USB helpers, Keychain reads, `wifi.tsv` parser, silence guard, `su` stdin broadcast push |
| Step definitions | `scripts/hydracam_lib/court_enroll_steps.py` | Ordered enrollment pipeline and boot-loop recovery helper (`boot_loop_rescue`) |
| Phone boot hook | `scripts/court_phone_setup/court-boot.sh` | Termux:Boot / `boot_completed` hook setting volume 0, charging cap, Wi-Fi stay-on, sshd |
| Phone Termux SSH setup | `scripts/court_phone_setup/termux-ssh.sh` | Configures Termux OpenSSH daemon and `authorized_keys` on the phone |
| Phone charge limiter | `scripts/court_phone_setup/charge-cap.sh` | Rooted battery `batt_slate_mode` controller keeping court phones within safe charge bounds |

## Canonical K2 Alignment (C1 1.29)

Court Cloud issues one canonical `deviceId` and `deviceSecret` per physical
phone slot instead of maintaining split fleet-inventory identities.

1. **IDs and aliases**: `resolve_device_id` checks existing aliases (`adb-serial`
   and optional `fleet-host`) first, verifies no cross-device alias conflict,
   and falls back to current slot assignments before minting a new `deviceId`.
2. **Idempotent enrollment (`enroll_single_k2_device`)**:
   - Re-checks `GET /health` against `C1_CONTRACT_VERSION = "1.29"`.
   - Re-uses an existing record by `deviceId`, `/internal/v1/devices/:id/assign`
     when moving courts/slots, or `POST /internal/v1/devices` when new or when
     `--rotate-secret` is requested (`mountRev` increments on the same record).
   - Verifies credentials immediately via `POST /device/v1/token` using a
     no-redirect HTTP opener (`_NoRedirectHandler`) so secrets are never leaked
     across redirects, matching `CourtAuth.kt`.
   - Upserts `adb-serial` and `fleet-host` aliases in `/internal/v1/aliases`.
3. **Android push**: Sends `com.amaia23.hydracam.court.ENROLL` (or `.CLEAR`) to
   `com.amaia23.hydracam.court/.CourtEnrollReceiver` over `su` stdin, quoting
   arguments with `shlex` so secrets never appear in host or shell `argv`.
4. **URL guard**: `validate_k2_url` rejects `https://kvisor.com` (marketing
   landing page) and non-HTTPS remote URLs; loopback `http://127.0.0.1` and
   `http://localhost` remain allowed for local mock testing.

## Workflows

### 1. Enrolling or Re-enrolling an Already Brought-Up Phone

Requires `COURT_CLOUD_ADMIN_TOKEN` (or `--admin-token-env`) in the environment:

```bash
python3 scripts/court_k2_enroll.py \
  --court airport-squash-2 \
  --slot left \
  --serial RF8M40MT6AW \
  --name court-s10e-3
```

To push an existing `0o600` credentials file across one or more devices:

```bash
python3 scripts/court_k2_enroll.py \
  --creds ~/.config/hydracam/court-devices.json \
  all
```

To clear K2 credentials from a decommissioned device:

```bash
python3 scripts/court_k2_enroll.py --serial RF8M40MT6AW --clear
```

### 2. Full Phone Bring-Up (Stock Samsung to K2-Enrolled)

```bash
python3 scripts/court_phone_setup.py RF8M40MT6AW \
  --name court-s10e-3 \
  --court airport-squash-2 \
  --slot left \
  --apk build/app/outputs/flutter-apk/app-court-release.apk
```

Use `--status` to inspect step progress without mutating the phone, and
`--from <step>` to clear a step and all subsequent steps before re-running.

## Step Order and Boot-Loop Prevention

`build_steps` preserves the strict ordering required to root Samsung Exynos SAR
devices without losing KnoxGuard state, triggering boot loops, or interrupting
other phones:

1. `preflight` -> `identify` -> `oem-unlock`: checks per-device PID lock,
   root kit SHA1s, `heimdall`, daily reboot cap, and toggles OEM unlock via
   `uiautomator`.
2. `bootloader-unlock` -> `kg-online` (for `blue-screen` targets): waits at
   least **90 seconds online** after unlocking so Samsung KnoxGuard clears
   `Prenormal` before custom images are flashed.
3. `download-mode` -> `flash` -> `recovery-wipe`: Samsung download mode has no
   ADB serial, so `download-mode` enforces one flashing phone on USB at a time.
   For `magisk-recovery` (S10e), flashing both `RECOVERY` (`recovery-magisk-v2.img`)
   and non-stock `BOOT` (`boot-magisk-sar.img`) prevents
   `/vendor/bin/install-recovery.sh` from overwriting Magisk recovery on boot,
   and `recovery-wipe` wipes data before first boot so `/data` never boot-loops.
4. `setup` -> `verify-unlock` -> `wifi`: single interactive setup wizard pass,
   then automated Wi-Fi provisioning from local `~/.config/hydracam/wifi.tsv`.
5. `root-boot` -> `magisk-shell` -> `remote-access` -> `tailscale`: reboots into
   Magisk-rooted OS (`adb reboot recovery`), installs/grants `com.topjohnwu.magisk`,
   configures Termux sshd + `court-boot.sh`, and optionally invokes a Tailscale
   rollout helper.
6. `hardening` -> `google-account` -> `hydracam` -> `pin-lock` -> `k2-enroll` ->
   `reboot-test`:
   - `hardening`: disables Samsung Device care auto-restart/app-optimization and
     installs charge bounds (`charge-cap.sh`).
   - `google-account`: skipped unless `--google-account` is provided; no fleet
     email is hardcoded in the repo.
   - `hydracam`: installs `com.amaia23.hydracam.court`, grants runtime
     permissions, configures Magisk root and `freecess` background whitelist.
   - `pin-lock`: reads the device PIN from macOS Keychain (account defaults to
     device serial) unless `--skip-pin`.
   - `k2-enroll`: executes `enroll_single_k2_device` against K2 Court Cloud and
     pushes credentials to `CourtEnrollReceiver`.
   - `reboot-test`: reboots via the profile's rooted reboot command and verifies
     root (`uid=0`) and silence after boot.

Every ADB-capable step starts by muting all audio streams (`ensure_silent`) so
reboots inside a venue never chime.

## Hardware Profiles

| Model | Label | Chipset | Root method | Tested |
| --- | --- | --- | --- | --- |
| `SM-G970F` | S10e | Exynos 9820 | `magisk-recovery` | Yes |
| `SM-G960F` | S9 | Exynos 9810 | `twrp` | No (`--allow-untested`) |
| `SM-G935F` | S7 edge | Exynos 8890 | `twrp` | No (`--allow-untested`) |
| `SM-G780G` | S20 FE | Snapdragon 865 | `magisk-boot` | No (`--allow-untested`) |
| `SM-G781B` | S20 FE 5G | Snapdragon 865 | `magisk-boot` | No (`--allow-untested`) |

## Local Secrets Contract

No credentials, Wi-Fi PSKs, PINs, or fleet email addresses live in git:

- K2 admin bearer token: environment variable named by `--admin-token-env`
  (default `COURT_CLOUD_ADMIN_TOKEN`).
- Enrolled device credential cache: `~/.config/hydracam/court-devices.json`
  written atomically with mode `0o600` (step state files strip `secret`).
- Wi-Fi table: `~/.config/hydracam/wifi.tsv` (override via
  `HYDRACAM_COURT_WIFI_TSV` or `--wifi-file`), supporting `@keychain:<service>`
  lookups.
- Google account and screen PIN secrets: macOS Keychain via `security`.

## Verification

Run host unit tests (uses mocked ADB/Heimdall and loopback HTTP, no attached
phone required) and shell/markdown checks:

```bash
python3 scripts/test_court_k2_enroll.py
python3 scripts/test_court_phone_setup.py
shellcheck --severity=error scripts/court_phone_setup/*.sh
npx --yes markdownlint-cli2 docs/control/court-phone-setup.md docs/control/README.md
```
