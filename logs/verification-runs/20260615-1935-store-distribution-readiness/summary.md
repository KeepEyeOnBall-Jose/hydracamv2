# Store Distribution Readiness

- Status: `partial`
- Date: 2026-06-15
- Scope: prepare HydraCam for App Store/TestFlight and Google Play testing at
  larger scale.

## Public Store URLs

Vercel deployment:

- Base: `https://store-site-ten.vercel.app/`
- Privacy Policy: `https://store-site-ten.vercel.app/privacy.html`
- Support: `https://store-site-ten.vercel.app/support.html`
- Account and Data Deletion:
  `https://store-site-ten.vercel.app/account-deletion.html`

Repo source for the deployed pages:

- `store-site/index.html`
- `store-site/privacy.html`
- `store-site/support.html`
- `store-site/account-deletion.html`
- `store-site/styles.css`

## Android

Fresh Android release bundle built with public store URL Dart defines:

- Artifact: `build/app/outputs/bundle/release/app-release.aab`
- SHA-256: `5c3a34aa3f9c8117769dc8ac8640f6bf2c55605fbab204c99e7a88c707eac387`
- Metadata sidecar:
  `build/app/outputs/bundle/release/app-release.aab.store-metadata.tsv`

Command:

```bash
HYDRACAM_PRIVACY_POLICY_URL=https://store-site-ten.vercel.app/privacy.html \
HYDRACAM_SUPPORT_URL=https://store-site-ten.vercel.app/support.html \
HYDRACAM_ACCOUNT_DELETION_URL=https://store-site-ten.vercel.app/account-deletion.html \
SKIP_CHECKS=1 bash scripts/build_store_artifacts.sh android
```

Upload preflight:

```bash
HYDRACAM_PRIVACY_POLICY_URL=https://store-site-ten.vercel.app/privacy.html \
HYDRACAM_SUPPORT_URL=https://store-site-ten.vercel.app/support.html \
HYDRACAM_ACCOUNT_DELETION_URL=https://store-site-ten.vercel.app/account-deletion.html \
bash scripts/check_store_readiness.sh upload-android
```

Post-helper-update rerun: the Android AAB was rebuilt after the release-helper
changes. `bash scripts/check_store_readiness.sh upload-android` passes the AAB,
metadata sidecar, packaged manifest, Auth0 redirect, and upload certificate
checks. One blocker remains: `GOOGLE_PLAY_JSON_KEY` is not set to a readable
service-account JSON file.

Current hardware UI smoke on attached Android hardware:

- Run: `android-s7-hardware-ui/summary.md`
- Device: Samsung S7 edge / SM-G935F / `9885e6503930304946`
- Result: passed setup and standby automation routes with screenshots.
- Screenshots: `360x640` PNGs for setup, setup-after-scroll, and standby.

This smoke uses the debug automation APK, so it proves current hardware UI and
overflow/log behavior on the attached S7. It does not replace the signed AAB
store artifact proof above.

## iOS

Fresh iOS archive was produced for:

- Bundle: `com.keepeyeonball`
- Version: `1.4.0`
- Build: `16`
- Team: `4RRY2QT7H8`
- Archive: `build/ios/archive/Runner.xcarchive`

The archive is signed with the local development identity:
`Apple Development: Jose Ramon Torregrosa Duran (4K56D5L8D9)`.

The App Store IPA export failed because the host has no local iOS Distribution
signing identity and Xcode command-line export reports no account:

```text
error: exportArchive No Accounts
error: exportArchive No signing certificate "iOS Distribution" found
```

Post-password retry on 2026-06-15:

- Chrome contained an active App Store Connect tab for
  `https://appstoreconnect.apple.com/apps/6738280411/distribution/ios/version/inflight`.
- `xcodebuild -exportArchive ... -allowProvisioningUpdates` still failed with
  `No Accounts` and missing `iOS Distribution`, so the browser login did not
  make an Xcode account or distribution signing identity available to CLI
  export.
- Local Fastlane has an old Spaceship cookie for `vectorblanco@gmail.com`, but
  `fastlane pilot builds --app_identifier com.keepeyeonball --username
  vectorblanco@gmail.com` reported the session was invalid, requested 2FA, and
  ended with `Unauthorized Access`.
- Chrome DOM automation is blocked because Chrome has `Allow JavaScript from
  Apple Events` disabled. Computer Use and Playwright browser inspection also
  timed out in this session.

Upload preflight with public URLs:

```bash
HYDRACAM_PRIVACY_POLICY_URL=https://store-site-ten.vercel.app/privacy.html \
HYDRACAM_SUPPORT_URL=https://store-site-ten.vercel.app/support.html \
HYDRACAM_ACCOUNT_DELETION_URL=https://store-site-ten.vercel.app/account-deletion.html \
bash scripts/check_store_readiness.sh upload-ios
```

Result: three blockers remain:

- iOS distribution signing identity is unavailable.
- iOS IPA is missing because export failed.
- `APP_STORE_CONNECT_API_KEY_PATH` is not set to a readable API key JSON file.

## Automation Added

Added `scripts/testflight_release_and_invite.sh`. Once the missing Apple
credentials are available, it:

1. Uses the public store URLs as Dart defines.
2. Builds the iOS store artifact.
3. Runs the iOS upload preflight.
4. Uploads/distributes that exact IPA through the existing fastlane lane.
5. Adds `jose@keepeyeonball.com` and `pkosiak@gmail.com` to
   `Hydracam External Testers` by default.

Post-password continuation updated this path so the scripts accept either:

- `APP_STORE_CONNECT_API_KEY_PATH` pointing to a Fastlane App Store Connect JSON
  key file.
- Apple's `.p8` triplet:
  `APP_STORE_CONNECT_API_KEY_P8_PATH`,
  `APP_STORE_CONNECT_API_KEY_ID`, and
  `APP_STORE_CONNECT_API_ISSUER_ID`.

When API credentials are configured, `scripts/build_store_artifacts.sh ios`
passes them to raw `xcodebuild -allowProvisioningUpdates` for automatic
signing/provisioning instead of relying only on a GUI-provisioned local
distribution identity.

The TestFlight helper now builds the IPA once, runs the upload preflight, uploads
and distributes that exact IPA via `ios upload_latest_beta`, then adds the
default testers. Internal helper calls use explicit `bash scripts/...`
invocations on this Mac.

Current dry-run behavior: the script exits before side effects with a clear
message when App Store Connect API credentials are missing.

Validation after the credential-path update:

- `bash -n scripts/build_store_artifacts.sh scripts/check_store_readiness.sh
  scripts/testflight_release_and_invite.sh scripts/google_play_internal_release.sh`
  passed.
- `ruby -c ios/fastlane/Fastfile` passed.
- `bash scripts/testflight_release_and_invite.sh` without Apple credentials
  exits `64` before side effects and prints both supported credential formats.
- `bash scripts/google_play_internal_release.sh` without Google credentials
  exits `64` before side effects and prints the required
  `GOOGLE_PLAY_JSON_KEY` command shape.
- A fake `.p8` triplet probe against `bash scripts/check_store_readiness.sh
  upload-ios` proves the readiness gate now accepts the alternate Apple API-key
  form; with that fake credential the only iOS upload preflight failure is the
  missing IPA.

Added `scripts/google_play_internal_release.sh`. Once the missing Google Play
service-account JSON is available, it:

1. Uses the public store URLs as Dart defines.
2. Runs the Android upload preflight.
3. Uploads the release to the Google Play internal testing track through the
   existing fastlane lane.

Current dry-run behavior: the script exits before side effects with a clear
message when `GOOGLE_PLAY_JSON_KEY` is missing.

## Current Device Inventory

- `adb devices -l` saw Samsung S7 edge `9885e6503930304946`.
- `xcrun xcdevice list --timeout 10` reported iPhone 12 Pro
  `00008101-000A68811E43001E` and iPad `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`
  unavailable with local-network/device-prep errors.
- `flutter devices --device-timeout 10` did not finish cleanly before manual
  interruption and only printed `Found 3 connected devices`; use ADB/CoreDevice
  inventory as the authoritative device state for this run.

## App Store Connect State

The logged-in App Store Connect page showed HydraCam TestFlight with:

- Existing iOS build: version `1.2.2`, build `14`
- Status: `Expired`
- Internal group: `Hydracam Testers`
- External group: `Hydracam External Testers`

No tester invitations should be sent as active until a fresh non-expired
TestFlight build is uploaded and associated with the tester group.

## Remaining Manual Inputs

Choose one Apple path:

1. Add the Apple Developer account for team `4RRY2QT7H8` in Xcode Settings >
   Accounts and let Xcode create/download an iOS Distribution certificate for
   `com.keepeyeonball`.
2. Or create an App Store Connect API key with sufficient Developer/App Manager
   access, save it outside the repo, and run `bash scripts/testflight_release_and_invite.sh`
   with either `APP_STORE_CONNECT_API_KEY_PATH` or the `.p8` key triplet
   documented above.

Android still needs `GOOGLE_PLAY_JSON_KEY` pointing to a readable Play Console
service-account JSON before `bash scripts/google_play_internal_release.sh` can
upload the already-built AAB to internal testing.
