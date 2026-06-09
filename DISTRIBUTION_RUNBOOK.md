# HydraCam Mobile Distribution Runbook

Last checked against official store docs: 2026-06-04.

This runbook covers iPhone App Store/TestFlight distribution and Android Google
Play distribution for HydraCam.

## Current App IDs

- iOS bundle ID: `com.keepeyeonball`
- Android package name: `com.amaia23.hydracam`
- Display name: `HydraCam`
- Current Flutter version: `1.4.0+16`
- Android target SDK: `35`

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
- iOS release build is produced with Xcode 26 or later and the iOS 26 SDK or
  later, matching Apple's current upload requirement.
- Real Android smoke test passes on at least one physical phone.
- Two-device HydraCam workflow passes on the same local network or hotspot:
  master discovery, slave connection, photo capture, video start/stop, local
  save, upload queue, and session end.
- Store privacy disclosures have been reviewed against the current code and
  backend behavior.

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
7. Add store metadata:
   - App name, subtitle, description, keywords.
   - Support URL and marketing URL.
   - Privacy policy URL.
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
  SHA-256:
  `c4aab71383a76ffe4385a9aea0717a69e4c76b09ba2be1a185c1807651fd210f`.
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
7. Create a Google Play service account for fastlane uploads, grant only the
   needed Play Console permissions, store the JSON key outside the repo, and set
   `GOOGLE_PLAY_JSON_KEY=/absolute/path/to/key.json`.

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

Verify these before each submission because the real answer depends on backend
storage and third-party SDK behavior:

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

Build both store artifacts:

```bash
scripts/build_store_artifacts.sh all
```

Build only Android:

```bash
scripts/build_store_artifacts.sh android
```

Build only iOS:

```bash
scripts/build_store_artifacts.sh ios
```

Skip checks only when a previous run in the same checkout already passed:

```bash
SKIP_CHECKS=1 scripts/build_store_artifacts.sh android
```

Expected outputs:

- iOS IPA: `build/ios/ipa/*.ipa`
- Android App Bundle: `build/app/outputs/bundle/release/app-release.aab`

## iPhone Beta To Friends

Use TestFlight. This is the least painful iPhone beta path because testers only
need the TestFlight app and an invite or public link.

Current 2026-06-09 state:

- Local App Store export works for `com.keepeyeonball`; latest verified IPA is
  `build/ios/ipa/HydraCam.ipa`.
- The IPA is signed for team `4RRY2QT7H8` with a cloud-managed Apple
  Distribution certificate and `iOS Team Store Provisioning Profile:
  com.keepeyeonball`.
- Upload still requires App Store Connect credentials. Provide
  `APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json`, or upload the
  IPA with Transporter / `xcrun altool` using an API key and issuer.

Recommended setup:

1. Upload a build with:

   ```bash
   cd ios
   bundle install
   APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json \
     bundle exec fastlane ios beta
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
cd ios
TESTFLIGHT_DISTRIBUTE_EXTERNAL=true \
TESTFLIGHT_GROUPS="Friends Beta" \
APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/api_key.json \
bundle exec fastlane ios beta
```

## Android Beta To Friends

Use Google Play Internal testing first. It is fast, private, and does not require
friends to install APKs manually.

1. Add friends' Google accounts to an Internal testing email list in Play
   Console.
2. Upload an internal build with:

   ```bash
   cd android
   bundle install
   GOOGLE_PLAY_JSON_KEY=/absolute/path/to/google-play-service-account.json \
     bundle exec fastlane android internal
   ```

3. Share the internal test opt-in link from Play Console.

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
6. Upload Android AAB to Play Console internal or production draft.
7. Run store pre-launch checks and review warnings.
8. Complete privacy, data safety, content rating, and review notes.
9. Submit App Store version for review.
10. Submit Google Play production release for review or staged rollout.
11. After approval, release gradually and monitor crashes, uploads, and user
    feedback.
