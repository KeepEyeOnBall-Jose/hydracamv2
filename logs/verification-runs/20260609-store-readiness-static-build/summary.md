# Store Readiness Static And Build Evidence

Date: 2026-06-09.

Scope: beta-first store readiness for TestFlight and Google Play internal or
closed testing. This evidence pack covers repo/static checks, local store
artifact builds, fastlane wrapper reproducibility, and known blockers. It does
not claim the release-lane hardware acceptance gate.

## Commands Run

- `git status -sb`
- `git diff --check`
- `scripts/ios_fastlane.sh --version`
- `scripts/android_fastlane.sh --version`
- `bash -n scripts/check_store_readiness.sh scripts/build_store_artifacts.sh scripts/ios_fastlane.sh scripts/android_fastlane.sh`
- `ruby -c android/fastlane/Fastfile`
- `ruby -c ios/fastlane/Fastfile`
- `flutter analyze`
- `flutter test`
- `scripts/build_store_artifacts.sh all`
- `BUILD_NAME=1.4.0 BUILD_NUMBER=17 scripts/build_store_artifacts.sh all`
- `flutter build appbundle --release`
- `SKIP_CHECKS=1 scripts/build_store_artifacts.sh ios`
- `plutil -lint ios/Runner/Info.plist`
- `plutil -lint ios/Runner/PrivacyInfo.xcprivacy`
- `scripts/check_store_readiness.sh local`
- `scripts/check_store_readiness.sh upload`
- `HYDRACAM_PRIVACY_POLICY_URL=... HYDRACAM_SUPPORT_URL=... HYDRACAM_ACCOUNT_DELETION_URL=... scripts/check_store_readiness.sh upload-android`
- `flutter pub run flutter_launcher_icons`
- `find ios/Runner/Assets.xcassets/AppIcon.appiconset -maxdepth 1 -type f -name '*.png' -print | sort | xargs file`
- `unzip -l build/ios/ipa/HydraCam.ipa | rg 'PrivacyInfo\\.xcprivacy|Info\\.plist|Runner\\.app/$'`
- `plutil -p <unzipped IPA>/Payload/Runner.app/Info.plist`
- `shasum -a 256 build/app/outputs/bundle/release/app-release.aab`
- `shasum -a 256 build/ios/ipa/HydraCam.ipa`
- `flutter pub get`
- `flutter test test/screens/login_screen_test.dart`
- `flutter test test/services/auth0_service_test.dart`
- `SKIP_CHECKS=1 scripts/build_store_artifacts.sh android`
- `sed -n '1,80p' build/app/outputs/bundle/release/app-release.aab.store-metadata.tsv`
- `git diff --check`

## Passing Evidence

- `git diff --check` passed after the release-readiness edits.
- `bash -n` passed for the store build, readiness, and fastlane wrapper shell
  scripts.
- `flutter analyze` passed with no issues on the current checkout.
- `flutter test` passed with `284` tests and `1` skipped on the current
  checkout.
- `test/screens/login_screen_test.dart` covers the Login screen account
  deletion request path before login, including the copyable request content
  and the configured public deletion URL handoff.
- `test/constants_release_hygiene_test.dart` now prevents release-visible
  placeholder sports centers, empty court groups, and placeholder court names
  from being bundled in the fallback master court picker.
- `flutter pub run flutter_launcher_icons` regenerated the Android and iOS
  launcher icons from `lib/assets/images/icon.png` after replacing the
  deprecated `flutter_icons` config key with `flutter_launcher_icons`.
- The iOS app icon catalog now references only `Icon-App-*.png` files, all
  referenced iOS app icons are valid PNG files, and the obsolete unreferenced
  JPEG files with `.png` names were removed from the asset catalog.
- `scripts/check_store_readiness.sh` now verifies referenced iOS app icons,
  Android launcher icon densities, artifact freshness, and public
  non-placeholder HTTPS store URLs. It also verifies Android release signing
  config does not fall back to debug signing, `android/key.properties` points to
  an existing upload keystore, and the AAB signer certificate matches the
  expected upload certificate fingerprint.
- Artifact freshness now includes the platform fastlane Appfile/Fastfile,
  Gemfile/Gemfile.lock, and wrapper scripts, so upload-lane changes cannot
  leave an older AAB or IPA looking current while generated README/report churn
  does not force an artifact rebuild.
- Store artifact builds now write ignored `*.store-metadata.tsv` sidecars next
  to each AAB/IPA. The metadata records the artifact SHA-256, builder path,
  build override environment, and compiled privacy/support/account-deletion
  URLs. Local preflight warns on missing or mismatched metadata; upload,
  `upload-ios`, and `upload-android` fail when required metadata does not match
  the artifact or current build environment.
- `scripts/check_store_readiness.sh` now supports platform-specific upload
  checks: `upload-ios` for TestFlight/App Store Connect prerequisites and
  `upload-android` for Google Play prerequisites. The combined `upload` mode
  still checks both stores.
- The same readiness preflight now guards against app-identity and platform
  policy drift: iOS Runner and fastlane must target `com.keepeyeonball`;
  Android manifest, Gradle namespace/applicationId, and fastlane must target
  `com.amaia23.hydracam`; Android `minSdk` must remain `24`, and
  `targetSdk`/`compileSdk` must stay at or above `35`.
- The readiness preflight now also guards the current `url_launcher_android`
  `6.3.23` pin and verifies the web manifest/index use HydraCam product
  metadata instead of Flutter template names or descriptions.
- The readiness preflight now verifies Auth0 mobile redirect schemes are
  app-specific, rejects the old generic `com.hydracam` callback scheme, and
  requires the Android source manifest to use Gradle's
  `appAuthRedirectScheme` placeholder so the Gradle app identity remains the
  single source for the packaged AppAuth callback scheme.
- `scripts/build_store_artifacts.sh` now removes the previous generated AAB or
  IPA before rebuilding that platform so failed exports cannot leave an older
  upload-looking artifact behind, and writes the sidecar metadata after each
  successful platform build.
- The Login screen now exposes pre-login Privacy Policy, Support, and Request
  Account Deletion actions. The store build wrapper and both fastlane lanes
  pass `HYDRACAM_PRIVACY_POLICY_URL`, `HYDRACAM_SUPPORT_URL`, and
  `HYDRACAM_ACCOUNT_DELETION_URL` as Dart defines when configured. The local
  AAB below was rebuilt without those values because the real public URLs are
  not published yet; upload mode still fails until they are provided and a fresh
  upload artifact is built.
- `docs/store/hydracam-account-deletion.md` now exists as the standalone draft
  for the public account/data deletion URL. The readiness preflight verifies
  the store privacy checklist plus the privacy, support, and deletion drafts
  cover the required account, media, diagnostics, local-network, requester
  verification, and retention-exception surfaces.
- `pubspec.yaml` now uses a release-appropriate package description instead of
  the default "A Flutter project" text.
- `url_launcher` is included for the pre-login privacy/support/deletion URL
  handoff.
  `url_launcher_android` is pinned to `6.3.23`; the unpinned `6.3.32` resolver
  selected AndroidX Core `1.17.0` and Browser `1.9.0`, which failed
  `:app:checkReleaseAarMetadata` under the current AGP `8.7.3` stack.
- `AuthService` now uses platform-specific app identity redirect URIs:
  `com.keepeyeonball://login-callback` on iOS and
  `com.amaia23.hydracam://login-callback` on Android. Focused Auth0 service
  tests cover login, refresh, and logout redirect URL propagation.
- `web/manifest.json` and `web/index.html` no longer expose the old
  `sport_cam_sync` / "A Flutter project" metadata; they now use the HydraCam
  app name and product description.
- `scripts/ios_fastlane.sh --version` resolved fastlane `2.228.0` through the
  locked Homebrew Ruby/Bundler path.
- `scripts/android_fastlane.sh --version` resolved fastlane `2.236.0` through
  the locked Homebrew Ruby/Bundler path.
- The platform fastlane READMEs now point to the repo wrapper scripts so the
  generated `[bundle exec] fastlane ...` examples do not hide the required
  Homebrew Ruby/Bundler path. The readiness preflight verifies those wrapper
  notes.
- `flutter test test/screens/login_screen_test.dart` passed with five focused
  widget tests covering mobile-only Auth0 error handling, the account-deletion
  request dialog, configured deletion URL launch, configured privacy/support
  URL launch, and the fallback in-app privacy text when a public URL is not
  compiled into the local build.
- `scripts/build_store_artifacts.sh all` passed with the default
  `1.4.0+16` version. The wrapper ran dependency resolution,
  `flutter analyze`, `flutter test`, Android AAB build, and iOS App Store IPA
  export. The later iOS metadata/privacy-manifest edits were validated with a
  targeted default iOS App Store IPA export.
- Current-source default `1.4.0+16` Android AAB SHA-256:
  `39475a054693bdca4b55bbe85a67d9eb5b1c00cc73af9a8ee9e284ae69455dbc`.
- Last successful default `1.4.0+16` iOS IPA SHA-256, before the later bundled
  court-fallback and launcher-icon cleanup:
  `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`.
- `BUILD_NAME=1.4.0 BUILD_NUMBER=17 scripts/build_store_artifacts.sh all`
  also passed the full wrapper path before the later iOS privacy-manifest
  rebuild. Rerun this override before uploading a build-number-17 artifact.
- Pre-privacy-manifest override `1.4.0+17` Android AAB SHA-256:
  `4de67e7df246b9c88c99c6598d887992a0f9d7e892f282a102d972dfd67a6b02`.
- Pre-privacy-manifest override `1.4.0+17` iOS IPA SHA-256:
  `7ec7a6a90e064cc6b1cac12d5c5ccd8adf2972926b05251eca67ad7f610c6895`.
- A prior current-source `SKIP_CHECKS=1 scripts/build_store_artifacts.sh all`
  rebuilt the Android AAB successfully and produced SHA-256
  `f704063009e3289528c578c2972758365fe02269d78461d72743cbcfbd4e4e93`.
  The same command archived iOS but failed during App Store IPA export because
  no Apple/iOS Distribution signing identity or Xcode account was available.
- After the launcher-icon, signing-hardening, privacy/support/deletion URL
  handoff cleanup, and Auth0 redirect-scheme alignment, the Android AAB was rebuilt
  from a removed output file with
  `SKIP_CHECKS=1 scripts/build_store_artifacts.sh android`; the current AAB
  SHA-256 is
  `39475a054693bdca4b55bbe85a67d9eb5b1c00cc73af9a8ee9e284ae69455dbc` and is
  fresh against Android release inputs. A later rebuild after sidecar support
  kept the same AAB SHA-256 and wrote
  `build/app/outputs/bundle/release/app-release.aab.store-metadata.tsv` with
  metadata format `HydraCamStoreArtifactMetadataV1`, platform `android`, the
  same artifact SHA-256, builder `scripts/build_store_artifacts.sh`, and empty
  privacy/support/deletion URL fields because the real public URLs are not
  published yet. The packaged Android manifest contains `com.amaia23.hydracam`
  with `login-callback` and no packaged `com.hydracam` callback scheme.
  `keytool -printcert -jarfile` confirms the AAB signer SHA-256 fingerprint is
  `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`,
  matching `android/amaia23-hydracam-upload-certificate-20260609.pem`.
- The follow-up Android AppAuth placeholder cleanup kept the same packaged AAB
  SHA-256, and a bundle manifest scan still shows `com.amaia23.hydracam` plus
  `login-callback` with no `com.hydracam` callback scheme.
- `scripts/check_store_readiness.sh local` now inspects the packaged AAB
  manifest and passes the AppAuth receiver, `login-callback` host,
  `com.amaia23.hydracam` redirect scheme, and no-`com.hydracam` packaged
  callback checks.
- `ios/Runner/Info.plist` passed `plutil -lint` after removing the Dart VM
  Bonjour services, tightening photo-library permission descriptions, and
  declaring `ITSAppUsesNonExemptEncryption=false`.
- A source scan found no custom non-exempt cryptography in app code; the only
  relevant runtime security surfaces are normal platform/network security,
  Auth0, and secure token storage.
- `ios/Runner/PrivacyInfo.xcprivacy` passed `plutil -lint`, is referenced by
  the Runner resources phase, and is validated by the local store preflight.
- `SKIP_CHECKS=1 scripts/build_store_artifacts.sh ios` passed after the
  Info.plist/privacy-manifest/export-compliance cleanup and exported default
  `1.4.0+16` IPA SHA-256
  `385e08c05b7213b0b5c199a4621198b0d2b0f356034c69f5fa89ebe85ab0dc08`.
  That IPA is older than the fallback court-data and launcher-icon cleanup, was
  removed from `build/ios/ipa/`, and must be rebuilt after signing is restored.
- Before removal, `unzip -l build/ios/ipa/HydraCam.ipa` confirmed
  `Payload/Runner.app/PrivacyInfo.xcprivacy` is bundled in the exported IPA.
- The then-built IPA `Payload/Runner.app/Info.plist` confirmed bundle
  `com.keepeyeonball`, version `1.4.0`, build `16`, and
  `ITSAppUsesNonExemptEncryption=false`.
- `scripts/check_store_readiness.sh local` now fails with one local blocker:
  the macOS keychain has no Apple/iOS Distribution signing identity. It also
  verifies the preserved iOS/Android app IDs, fastlane Appfiles, Android SDK
  floor, Android target/compile SDK policy, the Login screen
  privacy/support/account-deletion paths and Dart defines, and the Android AAB
  metadata sidecar, and warns that the current IPA is missing, plus five
  warnings for missing external submission values; current summary is
  `1 failure(s), 6 warning(s)`. Latest output:
  `check-store-readiness-local-latest.log`.
- `scripts/check_store_readiness.sh upload` failed as intended with seven
  failures: no Apple/iOS Distribution signing identity, missing current IPA,
  missing `APP_STORE_CONNECT_API_KEY_PATH`, missing `GOOGLE_PLAY_JSON_KEY`,
  missing public HTTPS `HYDRACAM_PRIVACY_POLICY_URL`, missing public HTTPS
  `HYDRACAM_SUPPORT_URL`, and missing public HTTPS
  `HYDRACAM_ACCOUNT_DELETION_URL`. A placeholder URL probe using `example.com`
  and `localhost` also failed the public-URL gate. Latest output:
  `check-store-readiness-upload-latest.log`.
- `scripts/check_store_readiness.sh upload-ios` failed as intended with six
  iOS/TestFlight blockers: no Apple/iOS Distribution signing identity, missing
  current IPA, missing `APP_STORE_CONNECT_API_KEY_PATH`, and the three missing
  public HTTPS store URLs. It does not fail on missing Google Play credentials.
  Latest output: `check-store-readiness-upload-ios-latest.log`.
- `scripts/check_store_readiness.sh upload-android` failed as intended with
  four Play blockers: missing `GOOGLE_PLAY_JSON_KEY` and the three missing
  public HTTPS store URLs. It confirms the current Android AAB, sidecar
  metadata, and signer, and does not fail on missing iOS signing or IPA state.
  Latest output:
  `check-store-readiness-upload-android-latest.log`.
- A targeted URL-mismatch probe using valid-looking public HTTPS URL
  environment values against the current no-URL local AAB failed as intended
  with `Android AAB store metadata mismatch:
  HYDRACAM_PRIVACY_POLICY_URL HYDRACAM_SUPPORT_URL
  HYDRACAM_ACCOUNT_DELETION_URL`, while the same run passed the URL syntax
  checks and kept `GOOGLE_PLAY_JSON_KEY` as the only credential blocker.
  Latest output:
  `check-store-readiness-upload-android-url-mismatch-probe.log`.

## Known Non-Blocking Warnings

- Flutter reports `63` packages with newer versions incompatible with current
  dependency constraints.
- Flutter warns that `photo_manager`, `permission_handler_apple`, and
  `disk_space_plus` do not yet support Swift Package Manager for iOS, and
  `photo_manager` does not yet support Swift Package Manager for macOS.
- Flutter warns that Android Gradle `8.10.2`, Android Gradle Plugin `8.7.3`,
  Kotlin `2.1.0`, and legacy Kotlin Gradle Plugin usage will become unsupported
  in a future Flutter release.
- A direct Android toolchain bump to Gradle `8.14.5`, AGP `8.11.1`, and Kotlin
  `2.2.20` was attempted, but `flutter build appbundle --release` did not
  finish in the validation window and was terminated after `652.2s` with exit
  `143`. The repo was restored to the last proven Android store-build
  toolchain.
- `url_launcher_android` must remain pinned below `6.3.29` until the Android
  toolchain upgrade is proven, because newer plugin releases require AndroidX
  metadata that rejects AGP `8.7.3`.

## Submission Blockers

- `APP_STORE_CONNECT_API_KEY_PATH` is not set locally; no `AuthKey_*.p8` or
  `FASTLANE_SESSION` was found for TestFlight upload.
- Local iOS App Store IPA export is blocked: `security find-identity -v -p
  codesigning` shows Apple Development identities only, and the current-source
  export failed with `No Accounts` / no `iOS Distribution` signing certificate.
  No current `build/ios/ipa/HydraCam.ipa` remains on disk; rebuild it after
  signing is restored before any upload.
- `GOOGLE_PLAY_JSON_KEY` is not set locally; Play Console ownership for
  `com.amaia23.hydracam` is still unverified.
- Public Privacy Policy, Support, and account/data deletion URL drafts exist in
  `docs/store/` but are not published as non-placeholder HTTPS URLs. A public
  account-deletion URL is required for upload mode while HydraCam exposes Auth0
  account functionality.
- Auth0 tenant settings must be updated before beta login testing so Allowed
  Callback URLs and Allowed Logout URLs include
  `com.keepeyeonball://login-callback` and
  `com.amaia23.hydracam://login-callback`.
- Store privacy labels and Google Data Safety still need owner/backend review.
- This pack did not run release-lane hardware acceptance. Before beta, run
  iPhone, iPad, and at least two supported Android devices. Before production,
  run the two-device master/slave capture workflow on the same LAN or hotspot.
