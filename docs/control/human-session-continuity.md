# Human session continuity — 9 October 2026

Owner: client-auth chat 01a1207f. Baseline `6e83866bd`, branch
`codex/hydracam-human-session-20261009`. Primary checkout preserved.

## Behavior and boundaries

- Android/iOS: flutter_appauth 12, Code + PKCE, OS secure storage. Android API 24
  floor and callbacks remain unchanged. No desktop/web interactive login added.
- Concurrent restoration shares one refresh. Offline/authority failures retain
  credentials with a two-second retry cooldown; explicit OAuth `invalid_grant`
  clears them. Logout fences late refresh/GUID results. Cancelled login retains
  the previously accepted session. Rejected identity is removed from memory even
  if OS credential deletion fails; failed durable deletion still needs retry.
- Credential rotations replace one secure-store JSON envelope. A failed write
  keeps the new rotation in memory for persistence retry, avoiding an unnecessary
  second exchange. A process death before OS storage commits remains unrecoverable.
- Capture metadata records issuer + subject. Loading a capture does not transfer
  ownership; anonymous/other-account restoration is refused without changing its
  metadata/media. Upload admission checks the current identity for queued work.
  Already-dispatched requests cannot be recalled by this client change.
- Legacy/delegated captures have no human identity and remain usable only in their
  existing anonymous/delegated mode. A new login does not claim legacy files.
- Backend HTTP still uses `M2MAuthService`; human restoration is **not** delegated
  API authorization or server-side cross-user isolation. Machine/API workstream
  must replace/verify that contract. No token, secret or tenant lifetime changed.

## Migration and rollback

The new store reads `auth0_credentials_v1` first, then the four legacy Auth0 keys.
The next successful login/refresh commits the envelope before removing legacy
keys. No capture, media or draft key is removed. Logout removes only these auth
keys, legacy first, to avoid falling back to a prior account after interruption.

An older binary cannot read the new envelope, so binary rollback after migration
requires interactive sign-in. Never recreate old consumed refresh tokens. Roll
forward to this reader to retain the current envelope. Old binaries also do not
understand capture ownership: do not downgrade an account-switching installation
until affected capture uploads are paused and its original owner is confirmed.
Preserve app data/media through install and rollback; never uninstall to test an
upgrade. Test on a supported real Android/iOS device before release.

## Validation and release gates

`bash scripts/check_human_session.sh` runs format, serial full tests and analyze.
Remote host: `keob-hetzner-dev`, isolated `/home/jose/work/human-session-01a1207f/hydracam`,
Flutter 3.47.6/Dart 3.13.5. The lockfile includes its five SDK-pinned
updates (intl, matcher, meta, test_api, vector_math); no auth dependency changed.
Unit tests use auth/storage doubles; they do not establish
live-account/device acceptance. Results belong in this repository’s TASK_BOARD.md.

Real-device cold start, force-stop/relaunch, in-place update, access-token expiry,
refresh revocation, offline recovery, cancelled login, same-email/different-subject
switch and preserved real-capture upload remain acceptance gates. Android device
inventory was empty; Apple devices were unavailable. Hetzner has Flutter but no
Android SDK in its configured/common locations; APK compile is blocked there.
The Android-arm64 bundle attempt also failed because native build hooks require
the Android SDK. No bundle/APK compile proof. Preserve the busy Mac; provision
the remote Android SDK/JDK before the native release gate.

The separate HydraCamWeb host lives in `hydracamasp`. Its Azure app is currently
only a forwarding bridge. Live legacy Web is on `media-timeline-vps`, with an
existing durable Data Protection bind mount. Do not infer missing cookie keys
from Azure’s disabled App Service storage setting.

## Recorded validation

On `keob-hetzner-dev`: `bash scripts/check_human_session.sh` ran with 3 GiB RAM,
one CPU and a 900-second ceiling. Format passed; `flutter test --no-pub
--concurrency=1 --reporter=expanded`: 726 passed, one live wearable-upload proof
skipped because its explicit service/fixture opt-in was absent. `flutter analyze
--no-pub`: no issues. `flutter build bundle --no-pub --target-platform=android-arm64`
failed at native build hooks: Android SDK not found. JDK/SDK also absent on the
physical host/common paths and existing remote container images. Local format,
`bash -n scripts/check_human_session.sh`, and `git diff --check` passed.
