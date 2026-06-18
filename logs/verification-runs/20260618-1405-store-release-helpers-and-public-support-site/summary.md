# Evidence Run: Store release helpers and public support site

- Source: docs/control/store-privacy-and-metadata.md
- Slug: `store-release-helpers-and-public-support-site`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Release helper shell scripts and Fastfile parse cleanly
- [x] Public privacy support and account-deletion URLs return HTTP 200
- [x] Readiness preflight reports missing credentials and unrelated dependency-pin blocker truthfully

## Device Matrix

- No device proof was required for this docs/script/static-site slice.

## Evidence

- `commands.log` records:
  - `bash -n` for `scripts/build_store_artifacts.sh`,
    `scripts/check_store_readiness.sh`,
    `scripts/google_play_internal_release.sh`, and
    `scripts/testflight_release_and_invite.sh`.
  - `ruby -c ios/fastlane/Fastfile`.
  - HTTP HEAD checks for the deployed privacy, support, and account-deletion
    pages; all returned `200`.
  - `bash scripts/check_store_readiness.sh local`, which returned `1` with two
    expected blockers in this dirty checkout: no local iOS Distribution or App
    Store Connect signing credential, and the separate unstaged pubspec/toolchain
    slice currently unpins `url_launcher_android`.
  - Release-file `git diff --check` passed.

## Result

- Final disposition: partial but commit-ready for helper/site source changes.
  The scripts parse and public URLs are reachable. Actual store upload remains
  blocked until App Store Connect / Google Play credentials are configured and
  the separate Android dependency/toolchain pin decision is resolved.
