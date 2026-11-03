# Multi-Surface Deploy Verification — 2026-08-26

Run of the post-audit branch `claude/project-audit-tooling-17db82` at commit
`02421a06`, building and exercising every deployment surface reachable from the
macOS dev host.

- App version: `1.4.0+19`
- Flutter: `3.44.1` (stable)
- Host: macOS 26.5.2, darwin-arm64

Per `docs/control/evidence-first-loop.md` (Evidence Storage Policy, 2026-08-26)
this pack keeps the summary and `commands.log` only. Build artifacts stay on the
capture host under `build/` and are not committed.

## Build matrix

| Surface | Command | Result | Artifact | Size |
| ------- | ------- | ------ | -------- | ---- |
| Web | `flutter build web --release` | pass | `build/web` | 42 MB |
| macOS | `flutter build macos --release` | pass | `build/macos/Build/Products/Release/HydraCam.app` | 51 MB |
| Android | `flutter build apk --debug` | pass | `build/app/outputs/flutter-apk/app-debug.apk` | 162 MB |
| iOS | `flutter build ios --release --no-codesign` | pass | `build/ios/iphoneos/Runner.app` | 22 MB |

Android release signing was not attempted: `android/key.properties` and the
keystore are absent on this host (gitignored by design), so `hasReleaseKeystore`
is false and only a debug-signed APK is producible here. iOS was built unsigned
for the same reason — signing identities were deliberately not inspected.

## Runtime verification — macOS release binary

The macOS release build was launched and exercised as a real deployment, not
just a compile check. This is the first end-to-end confirmation that the Phase 4
to Phase 6 refactors (master server fixes, API service split, screen controller
extraction) behave correctly in a release artifact rather than under the test
harness.

- Process started and stayed resident: pid alive, RSS ~113 MB.
- `MasterServer` bound its listening socket: `TCP *:4040 (LISTEN)`.
- Protocol responses matched `test/master/master_server_test.dart` exactly:

| Request | Observed | Matches unit assertion |
| ------- | -------- | ---------------------- |
| `GET /` | `403` | yes — non-`/ws` paths rejected |
| `GET /healthz` | `403` | yes — non-`/ws` paths rejected |
| `GET /ws` without upgrade headers | `400` | yes — documented client behaviour |
| `GET /ws` with WebSocket upgrade handshake | `101 Switching Protocols` | yes — upgrade accepted |

The app was then quit cleanly.

## Static and test gates at this commit

- `flutter analyze --no-pub`: no issues.
- `dart format --output=none --set-exit-if-changed lib test`: clean (219 files).
- `flutter test --no-pub`: 718 passed, 1 skipped (known `photo_manager` host skip).
- `scripts/test_*.py`: 18 passed (excludes `test_endpoints.py`, a live-network probe).
- `shellcheck --severity=error scripts/*.sh *.sh`: clean.
- `npx markdownlint-cli2` over README/AGENTS/docs/control: 0 issues.
- `bash scripts/agent_gate.sh`: pass.

## Pre-deploy gate, positive and negative

`./verify.sh` was run end to end as the real pre-deploy gate (clean, pub get,
format, analyze, full test suite, debug APK build) and exited `0`, printing
`VERIFICATION COMPLETE`.

The gate was then negative-tested, because the defect this script carried before
2026-08-26 was that a red suite still reached `VERIFICATION COMPLETE`. A
deliberately failing test was added at `test/tmp_gate_negative_test.dart` and the
gate re-run:

- exit status `1`
- `flutter test` reported `+718 ~1 -1: Some tests failed.`
- the script printed `flutter test failed` and aborted
- `VERIFICATION COMPLETE` and `Ready to deploy` were absent from the output

The temporary test was removed afterwards; the tree is clean. This confirms the
`|| true` plus output-grep success detection is genuinely gone and the gate now
fails closed.

## Surfaces not reached from this host

- `git push` of the branch and the follow-on pull request were blocked by a
  local safety check, so nothing was published to the `github` remote. The
  branch exists only locally; CI has therefore not yet run on a real runner.
- Google Play and App Store Connect submission require credentials
  (`GOOGLE_PLAY_JSON_KEY`, App Store Connect API key) that are not present, and
  publishing to either store is an owner decision rather than an agent action.
- The `store-site/` static site was not deployed; that is a public content
  change and was left for the owner.
