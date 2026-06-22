# HydraCam Mobile Distribution Runbook

Last checked against official store docs: 2026-06-09.

This runbook covers iPhone App Store/TestFlight distribution and Android Google
Play distribution for HydraCam.

Latest static/build evidence:
`logs/verification-runs/20260609-store-readiness-static-build/summary.md`.

## Current App IDs

- iOS bundle ID: `com.keepeyeonball`
- Android package name: `com.amaia23.hydracam`
- Display name: `HydraCam`
- Current Flutter version: `1.4.0+18`
- Android target SDK: `35`
- Latest verified Android AAB SHA-256 (`1.4.0+18`, built 2026-06-21 with
  current public store URLs):
  `d570e6ebe507ad2a6f2de5c499cf5bd2cd2f162932bde63e47a728b51c75c8d9`
- Historical default iOS IPA SHA-256 (`1.4.0+16`, prior to bundled
  court-fallback and launcher-icon cleanup):
  `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`
- Current-source iOS App Store IPA export is blocked locally until an Apple/iOS
  Distribution signing identity or Xcode account is available again; no current
  IPA is kept in `build/ios/ipa/`.

Treat app IDs as permanent once published. Changing either ID creates a different
store app.

## Release Gates

Do not submit a production build until all gates pass:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Real iPhone smoke test passes on the intended release/profile lane. Debug
  launches through Flutter tooling are useful development evidence, but they do
  not prove that the app starts from the Home Screen icon.
- iOS release build is produced with Xcode 26 or later and an iOS 26 SDK or
  later, matching Apple's current upload requirement. The current local host
  reports Xcode `26.5`.
- Real Android smoke test passes on at least one physical phone.
- Android release builds use the configured upload keystore only; debug-signing
  fallback is not allowed for store artifacts, and the built AAB signer
  certificate must match the published upload-certificate SHA-256 fingerprint.
- `scripts/check_store_readiness.sh local` verifies the preserved app IDs across
  platform manifests, Gradle, and fastlane: iOS `com.keepeyeonball`, Android
  `com.amaia23.hydracam`, Android `minSdk` 24, and Android target/compile SDK
  at or above 35.
- Two-device HydraCam workflow passes on the same local network or hotspot:
  master discovery, slave connection, photo capture, video start/stop, local
  save, upload queue, and session end.
- Store privacy disclosures have been reviewed against
  `docs/control/store-privacy-and-metadata.md`, current code, and backend
  behavior.
- The Login screen privacy policy, support, and account-deletion request paths
  are present. Public HTTPS privacy, support, and account-deletion URLs are
  configured for store forms and upload preflight. The store build wrapper and
  fastlane lanes compile those URLs into the app with
  `HYDRACAM_PRIVACY_POLICY_URL`, `HYDRACAM_SUPPORT_URL`, and
  `HYDRACAM_ACCOUNT_DELETION_URL`; rebuild after publishing the real URLs.
- Auth0 mobile callback and logout URLs use app-specific schemes, not the old
  generic `com.hydracam` scheme: iOS uses
  `com.keepeyeonball://login-callback`, and Android uses
  `com.amaia23.hydracam://login-callback` through the Gradle
  `appAuthRedirectScheme` manifest placeholder. Configure both in Auth0 Allowed
  Callback URLs and Allowed Logout URLs before beta login testing.
- `ios/Runner/PrivacyInfo.xcprivacy` is present in the Runner resources phase
  and matches the current code paths for required-reason APIs and collected
  app-functionality data.
- iOS and Android launcher icons are regenerated from
  `lib/assets/images/icon.png`; referenced iOS app icon files must be real PNG
  files, and Android launcher icon densities must be present.
- Web metadata, while outside the mobile store target, must still use HydraCam
  product naming and description instead of Flutter template text so public
  links and future web builds are not visibly unfinished.
- `ios/Runner/Info.plist` declares
  `ITSAppUsesNonExemptEncryption=false` for the current no-custom-cryptography
  app, avoiding a repeat App Store Connect missing-compliance prompt on upload.
- Local macOS signing has an Apple/iOS Distribution identity or a signed-in
  Xcode account capable of creating one. `scripts/check_store_readiness.sh
  local` fails this gate when only Apple Development identities are visible.

## One-Time Apple Setup

1. Enroll or confirm access to the Apple Developer Program.
2. In Certificates, Identifiers & Profiles, confirm bundle ID
   `com.keepeyeonball`.
3. In App Store Connect, create the HydraCam app record using that bundle ID.
4. Confirm `ios/fastlane/Appfile` values:
   - `app_identifier("com.keepeyeonball")`
   - `apple_id("jose@keepeyeonball.com")`
   - `team_id("4RRY2QT7H8")`
   - `itc_team_id("118432237")`
5. Set Xcode signing for the Runner target to the Apple team. Automatic signing
   is the easiest local setup.
6. Create an App Store Connect API key for automation. Store it outside the repo
   and point fastlane at it with `APP_STORE_CONNECT_API_KEY_PATH`.
7. In Auth0, add `com.keepeyeonball://login-callback` to Allowed Callback URLs
   and Allowed Logout URLs for the mobile application.
8. Add store metadata:
   - App name, subtitle, description, keywords.
   - Support URL and marketing URL.
   - Privacy policy URL.
   - Account deletion URL if Auth0 account creation remains enabled.
   - iPhone screenshots for required device sizes.
   - App Review contact details and demo credentials if login is required.
   - App privacy answers.

Official references:

- Apple App Store Connect workflow:
  https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/
- Apple upload builds:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Apple submit app:
  https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/
- Apple app privacy details:
  https://developer.apple.com/app-store/app-privacy-details/
- Apple SDK minimum requirements:
  https://developer.apple.com/news/upcoming-requirements/?id=02032026a
- Flutter iOS release:
  https://docs.flutter.dev/deployment/ios

## Physical iPhone Development Launch Modes

Debug builds are for Flutter tooling or Xcode. If a Debug build is started
directly from the Home Screen icon, iOS/Flutter can report that the debug
Flutter engine cannot be created without Flutter tooling or Xcode. Treat that
as expected Debug-mode behavior, not as a standalone app smoke pass.

For Home Screen icon testing before TestFlight, install a Profile build:

```bash
IOS_XCODE_DESTINATION_ID=00008101-000A68811E43001E \
IOS_DEVICE=AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
IOS_DEVELOPMENT_TEAM=4RRY2QT7H8 \
IOS_BUNDLE_ID=com.keepeyeonball \
scripts/ios_icon_launch_dev.sh
```

After install, start HydraCam by tapping the iOS icon. For repeatable command
evidence without attaching Flutter tooling:

```bash
xcrun devicectl device process launch \
  --device AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A \
  --terminate-existing \
  com.keepeyeonball
```

Use `flutter run -d <ios-udid> --debug` only when hot reload, the Dart VM
Service, or Flutter debugger attachment is required.

## One-Time Google Play Setup

Current recovery evidence from 2026-06-09:

- The Android package remains `com.amaia23.hydracam`.
- `jose@keepeyeonball.com` is a recognized Google account but was stopped at
  the Google password prompt in Chrome; Play Console ownership is not verified
  yet.
- `vectorblanco@gmail.com` is signed into Chrome, but
  `https://play.google.com/console/u/0/developers` redirects that account to the
  Play Console developer-account signup flow. The page says the currently
  signed-in Google Account will own any new developer account and ownership
  cannot be changed after creation.
- Read-only Gmail and historical `HydraCam Dev Process` sheet checks did not
  find Play Console ownership, invitation, package-registration, or Android
  distribution evidence for `com.amaia23.hydracam`.
- A new ignored AMAIA23/HydraCam upload keystore was created at
  `/Users/jose/.config/hydracam/secrets/android/amaia23-hydracam-upload-20260609.jks`.
- The public upload certificate is
  `android/amaia23-hydracam-upload-certificate-20260609.pem`.
- Use SHA-256 fingerprint
  `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`
  when registering the package or requesting an upload-key reset.
- `flutter build appbundle --release` now builds the signed AAB at
  `build/app/outputs/bundle/release/app-release.aab`; latest verified artifact
  SHA-256 for the current `1.4.0+18` build:
  `d570e6ebe507ad2a6f2de5c499cf5bd2cd2f162932bde63e47a728b51c75c8d9`.
- The release Gradle config no longer falls back to debug signing. The store
  readiness preflight verifies `android/key.properties`, the referenced upload
  keystore, app IDs, Android SDK floor, Android target/compile SDK policy, and
  the AAB signer fingerprint before upload.
- Full non-secret evidence:
  `logs/verification-runs/20260609-0405-amaia23-android-developer-profile-recovery/summary.md`.

1. Complete the `jose@keepeyeonball.com` sign-in and confirm whether that
   account owns the prior Play Console developer account. If it does, invite
   `vectorblanco@gmail.com` as an admin before making release changes.
2. If no prior account exists, create an organization Play Console developer
   account under the intended owner account before registering the package.
3. Create the Play Console app with package name `com.amaia23.hydracam`.
4. Enable Play App Signing.
5. Generate or recover an upload keystore and keep it backed up outside Git.
   The current recreated upload key is already wired through ignored
   `android/key.properties`; generate a new one only if intentionally replacing
   this recovery key.

   ```bash
   keytool -genkey -v \
     -keystore android/upload-keystore.jks \
     -keyalg RSA \
     -keysize 2048 \
     -validity 10000 \
     -alias upload
   ```

5. Copy `android/key.properties.example` to `android/key.properties`, fill in
   the real passwords, and keep both `android/key.properties` and the keystore
   out of Git.
6. Add Play Console setup:
   - Store listing, app category, contact details.
   - Privacy policy URL.
   - Data Safety form.
   - Content rating questionnaire.
   - Target countries.
   - App access instructions if reviewers need credentials.
7. In Auth0, add `com.amaia23.hydracam://login-callback` to Allowed Callback
   URLs and Allowed Logout URLs for the mobile application.
8. Create a Google Play service account for fastlane uploads, grant only the
   needed Play Console permissions, store the JSON key outside the repo, and set
   `GOOGLE_PLAY_JSON_KEY=/absolute/path/to/key.json`.
9. Use `scripts/android_fastlane.sh` from the repo root when the shell would
   otherwise choose `/usr/bin/bundle`; that wrapper forces the Homebrew
   Ruby/Bundler path used by the locked Android fastlane bundle.

Official references:

- Google Play release rollout:
  https://support.google.com/googleplay/android-developer/answer/9859348
- Google Play testing tracks:
  https://support.google.com/googleplay/android-developer/answer/9845334
- Google Play personal account testing requirement:
  https://support.google.com/googleplay/android-developer/answer/14151465
- Google Play Data safety:
  https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play target API requirements:
  https://developer.android.com/google/play/requirements/target-sdk
- Flutter Android release:
  https://docs.flutter.dev/deployment/android

## Store Privacy Inputs

Use `docs/control/store-privacy-and-metadata.md` as the working checklist and
publish the drafts in `docs/store/` for the privacy policy, support page, and
account/data deletion page, then verify the final answers before each
submission because the real answer depends on backend storage and third-party
SDK behavior:

- Media: photos, videos, and microphone audio are captured and may be uploaded.
- Location: requested on demand to identify the active recording venue.
- Identifiers: the app creates a device ID and uses Auth0 login data.
- Network data: local WebSocket communication exposes device/session messages on
  the local network; backend API calls upload session/media data.
- User content: manually selected gallery media can be added to a session.
- Diagnostics: app logs are local unless a future backend path uploads them.

App Store privacy labels and Google Play Data Safety must match the app,
backend, Auth0, and any SDKs included in the release build.

## Build Artifacts

Use the version in `pubspec.yaml` by default, or override with `BUILD_NAME` and
`BUILD_NUMBER`.

Known build warnings from Flutter 3.44:

- Android release builds still warn that Gradle `8.10.2`, Android Gradle Plugin
  `8.7.3`, and Kotlin `2.1.0` will be unsupported by a future Flutter release.
  A direct bump to Gradle `8.14.5`, AGP `8.11.1`, and Kotlin `2.2.20` was
  attempted on 2026-06-09, but `flutter build appbundle --release` did not
  finish in the validation window and was terminated after `652.2s` with exit
  code `143`. Keep the proven current toolchain for beta artifacts and handle
  this as an isolated Android toolchain upgrade before it becomes a hard build
  failure.
- `url_launcher_android` is pinned to `6.3.23` because `6.3.29+` pulls
  AndroidX Core `1.17.0` and Browser `1.9.0`, which require Android Gradle
  Plugin `8.9.1+`. Keep the pin until the Android toolchain upgrade is proven.
- Flutter also warns that several iOS/macOS plugins do not yet support Swift
  Package Manager and that Android app/plugin builds still use the legacy
  Kotlin Gradle Plugin path. These are future-compatibility issues, not current
  App Store or Play Console submission blockers while the verified builds pass.

Run the local readiness preflight before building or uploading:

```bash
scripts/check_store_readiness.sh local
```

Local mode verifies bundle/package IDs, display name, version, permissions,
launch assets, the iOS privacy manifest, fastlane wrappers, in-app
privacy/support/deletion paths, and artifact presence/freshness against
release-relevant source inputs. It also verifies that referenced iOS and
Android launcher icons are valid PNG assets, that the web manifest/index no
longer expose Flutter template metadata, and that `url_launcher_android`
remains pinned for the current Android toolchain. It includes fastlane
Appfile/Fastfile, Gemfile/Gemfile.lock, and wrapper scripts in artifact
freshness checks. It also checks each generated AAB/IPA metadata sidecar
(`*.store-metadata.tsv`) when an artifact exists, warning locally if the
artifact hash, build override, or compiled store URLs do not match the current
build environment. It warns, but does not fail, when external upload
credentials or public URLs are missing.

Before any real upload attempt, run upload mode with the required external
values:

```bash
APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/app-store-connect-api-key.json \
GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/check_store_readiness.sh upload
```

Combined upload mode fails until both credential files exist, all public store
URLs are non-placeholder HTTPS URLs, and the AAB/IPA artifacts are current
against release-relevant source inputs. It also requires the AAB/IPA metadata
sidecars to match the artifact hash, `BUILD_NAME`/`BUILD_NUMBER` overrides,
and the three compiled store URLs, so publish the URLs first and rebuild before
upload. Keep secret files outside this repo.

For a platform-specific beta check, use one of these narrower modes:

```bash
APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/app-store-connect-api-key.json \
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/check_store_readiness.sh upload-ios
```

```bash
GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/check_store_readiness.sh upload-android
```

`upload-ios` still requires the current IPA and App Store Connect credentials,
but does not fail on missing Google Play credentials. `upload-android` still
requires the current AAB and Google Play credentials, but does not fail on
missing iOS signing or IPA state.

Build both store artifacts:

```bash
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/build_store_artifacts.sh all
```

The wrapper removes the previous generated AAB/IPA before rebuilding that
platform and writes an ignored `*.store-metadata.tsv` sidecar next to each
artifact. If a build or export fails, do not reuse an older artifact left from a
prior run.

Build only Android:

```bash
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/build_store_artifacts.sh android
```

Build only iOS:

```bash
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/build_store_artifacts.sh ios
```

Skip checks only when a previous run in the same checkout already passed:

```bash
SKIP_CHECKS=1 scripts/build_store_artifacts.sh android
```

Expected outputs:

- iOS IPA: `build/ios/ipa/*.ipa`
- Android App Bundle: `build/app/outputs/bundle/release/app-release.aab`
- Store artifact metadata sidecars: `*.store-metadata.tsv` next to each
  generated AAB/IPA.

The 2026-06-09 wrapper validation also passed with
`BUILD_NAME=1.4.0 BUILD_NUMBER=17`; those validation artifacts had Android
SHA-256 `4de67e7df246b9c88c99c6598d887992a0f9d7e892f282a102d972dfd67a6b02`
and iOS SHA-256
`7ec7a6a90e064cc6b1cac12d5c5ccd8adf2972926b05251eca67ad7f610c6895`.

## iPhone Beta To Friends

Use TestFlight. This is the least painful iPhone beta path because testers only
need the TestFlight app and an invite or public link.

Current 2026-06-09 state:

- A prior local App Store export for `com.keepeyeonball` produced default
  `1.4.0+16` IPA SHA-256
  `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`, with
  `Payload/Runner.app/PrivacyInfo.xcprivacy` and
  `ITSAppUsesNonExemptEncryption=false` in the built app. That IPA predates the
  fallback-data and launcher-icon cleanups and has been removed from
  `build/ios/ipa/`.
- After the bundled court-fallback and launcher-icon cleanup, Android rebuilt
  successfully but current-source iOS export is blocked locally. `xcodebuild`
  archived `com.keepeyeonball` but `exportArchive` failed with `No Accounts`
  and no signing certificate `iOS Distribution` / `Apple Distribution` found.
- `security find-identity -v -p codesigning` currently reports Apple
  Development identities only and no local Distribution identity; restore the
  Xcode Apple account/certificate or install a Distribution certificate before
  retrying the current-source IPA export.
- Upload still requires App Store Connect credentials. Provide
  `APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json`, or upload the
  IPA with Transporter / `xcrun altool` using an API key and issuer.
- In this checkout, use `scripts/ios_fastlane.sh` from the repo root when the
  shell would otherwise choose `/usr/bin/bundle`; that wrapper forces the
  Homebrew Ruby/Bundler path required by `ios/Gemfile.lock`.

Recommended setup:

1. Upload a build from the repo root with:

   ```bash
   APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json \
   HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
   HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
   HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
     scripts/ios_fastlane.sh ios beta
   ```

2. In App Store Connect, create an external TestFlight group named
   `Friends Beta`.
3. Add the build to that group and submit it for Beta App Review if prompted.
4. After approval, enable a public link for the group and send that link to
   friends.

Apple currently supports up to 100 internal testers and up to 10,000 external
testers in TestFlight. External testing requires Beta App Review for the first
build of a version.

If you already created the `Friends Beta` external group, fastlane can upload and
assign the build:

```bash
TESTFLIGHT_DISTRIBUTE_EXTERNAL=true \
TESTFLIGHT_GROUPS="Friends Beta" \
APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json \
HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
scripts/ios_fastlane.sh ios beta
```

## Android Beta To Friends

Use Google Play Internal testing first. It is fast, private, and does not require
friends to install APKs manually.

Current 2026-06-21 state:

- Local Android App Bundle export works for `com.amaia23.hydracam`; the latest
  default `1.4.0+18` run produced Android AAB SHA-256
  `d570e6ebe507ad2a6f2de5c499cf5bd2cd2f162932bde63e47a728b51c75c8d9`
  with matching store metadata sidecar values for the current public privacy,
  support, and account-deletion URLs. Later override builds overwrite
  `build/app/outputs/bundle/release/app-release.aab`, so hash the artifact
  immediately before uploading.
- `GOOGLE_PLAY_JSON_KEY` is not set locally, so fastlane upload cannot run yet.
- Play Console account ownership for `com.amaia23.hydracam` is still unverified.

1. Add friends' Google accounts to an Internal testing email list in Play
   Console.
2. Upload an internal build with:

   ```bash
   GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
   HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
   HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
   HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
     bash scripts/google_play_release.sh internal
   ```

3. For a wider closed test after internal smoke, upload to the configured
   closed testing track:

   ```bash
   GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
   HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
   HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
   HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
     bash scripts/google_play_release.sh closed_beta beta
   ```

4. For production review, upload a draft first:

   ```bash
   GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
   HYDRACAM_PRIVACY_POLICY_URL="$PUBLISHED_HYDRACAM_PRIVACY_POLICY_URL" \
   HYDRACAM_SUPPORT_URL="$PUBLISHED_HYDRACAM_SUPPORT_URL" \
   HYDRACAM_ACCOUNT_DELETION_URL="$PUBLISHED_HYDRACAM_ACCOUNT_DELETION_URL" \
     bash scripts/google_play_release.sh production_draft
   ```

5. Share the internal or closed-test opt-in link from Play Console.

Google Play internal testing is intended for up to 100 trusted testers and can
make builds available quickly. For a wider pre-release group, use a closed test.

For newly created personal Play developer accounts, Google currently requires a
closed test with at least 12 opted-in testers for 14 continuous days before
production access can be requested. Plan this calendar time before launch.

## Production Release Flow

1. Freeze release scope.
2. Bump `version:` in `pubspec.yaml`.
3. Run release gates.
4. Build artifacts.
5. Upload iOS to App Store Connect/TestFlight.
6. Upload Android AAB to Play Console internal, closed testing, or production
   draft with `scripts/google_play_release.sh`.
7. Run store pre-launch checks and review warnings.
8. Complete privacy, data safety, content rating, and review notes.
9. Submit App Store version for review.
10. Submit Google Play production release for review or staged rollout.
11. After approval, release gradually and monitor crashes, uploads, and user
    feedback.
