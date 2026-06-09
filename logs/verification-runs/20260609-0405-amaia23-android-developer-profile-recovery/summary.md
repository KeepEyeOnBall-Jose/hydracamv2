# AMAIA23 Android Developer Profile Recovery

Date: 2026-06-09

## Scope

Recover or recreate the Android distribution profile state for HydraCam /
AMAIA23 Inteligencia Artificial.

## Local repo truth

- Android package name: `com.amaia23.hydracam`
- Existing release runbook: `DISTRIBUTION_RUNBOOK.md`
- Existing fastlane Android package config: `android/fastlane/Appfile`
- No prior `android/key.properties`, upload keystore, or Google Play service
  account key was found in the HydraCam checkout or nearby local source trees.
- Gmail/Drive checks found Google Developer Program premium payments for
  `vectorblanco@gmail.com`, but no concrete Google Play Console app/account
  mail or Drive credential artifact for `com.amaia23.hydracam`.
- Follow-up Chrome account check on 2026-06-09 found that
  `jose@keepeyeonball.com` is a recognized Google account. Chrome's current
  account chooser only had `vectorblanco@gmail.com` signed in, then "Use another
  account" with `jose@keepeyeonball.com` advanced to Google's password prompt.
  Play Console ownership remains unverified until that sign-in is completed.
- Continuation Chrome check on 2026-06-09 opened
  `https://play.google.com/console/u/0/developers` while signed in as
  `vectorblanco@gmail.com`; Play Console redirected to
  `https://play.google.com/console/u/0/signup` and showed the "Creating a Play
  Console developer account" flow. The page stated that
  `vectorblanco@gmail.com` would own any newly created developer account and
  that ownership cannot be changed after creation.
- Local `gcloud` account: `vectorblanco@gmail.com`

## Recreated local upload-signing profile

Created a new ignored Android upload keystore for AMAIA23/HydraCam:

- Private keystore path:
  `/Users/jose/.config/hydracam/secrets/android/amaia23-hydracam-upload-20260609.jks`
- Gradle signing config:
  `android/key.properties` (ignored by Git)
- Public upload certificate:
  `android/amaia23-hydracam-upload-certificate-20260609.pem`
- Key alias: `amaia23-hydracam-upload`
- Distinguished name:
  `CN=AMAIA23 Inteligencia Artificial SL, OU=HydraCam, O=AMAIA23 Inteligencia Artificial SL, L=Madrid, ST=Madrid, C=ES`
- Validity: 2026-06-09 through 2053-10-25
- SHA-256 certificate fingerprint:
  `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`

Do not commit the private keystore or `android/key.properties`.

## External account status

The in-app browser redirected
`https://play.google.com/console/u/0/developers` to the public Google Play
Console marketing page rather than an authenticated developer dashboard.

Chrome later proved that the currently signed-in `vectorblanco@gmail.com`
account has no visible Play Console developer account yet: the Play Console
developer URL opened the developer-account signup page. The account switcher
listed only `vectorblanco@gmail.com`; entering `jose@keepeyeonball.com` again
advanced to the Google password challenge. That Chrome tab was left open as a
handoff point and no password or 2FA code was entered.

Read-only Gmail checks in the connected `vectorblanco@gmail.com` mailbox found
no Play Console-specific sender, invite, app ownership, or package-registration
mail. `googleplay-noreply@google.com` hits were consumer Google Play / Google
One receipts, and `HydraCam` hits were App Store Connect iOS processing notices.
The historical `HydraCam Dev Process` sheet was shared from
`jose@keepeyeonball.com` on 2024-12-31, but targeted row searches for Android /
Google Play evidence in `Index`, `JAVI IMMEDIATE BACKLOG`, `Functional
Requirements`, `SYSTEM FEATURES`, and `Testing table` returned no Android
distribution rows.

Current evidence does not prove that an AMAIA23 Google Play Console developer
account/app exists. If it exists under `jose@keepeyeonball.com`, recovery must
continue after completing the Chrome sign-in currently stopped at the password
prompt. If it does not exist, create an Organization developer account for
AMAIA23 Inteligencia Artificial and use the new upload certificate above when
registering `com.amaia23.hydracam`.

For non-Play APK distribution, Android Developer Console package registration
also needs the same package name and SHA-256 signing-certificate fingerprint.

## Build verification

Command:

```bash
flutter build appbundle --release
```

Initial result: failed after the release signing config was accepted.

Initial blocker:

```text
/Users/jose/src/work/hydracamv2/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java:64: error: package dev.flutter.plugins.integration_test does not exist
      flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());
                                                                             ^
```

Root cause: the Flutter Gradle plugin deliberately excludes dev-dependency
plugins from release builds, but the generated Android plugin registrant still
included `integration_test`. `android/app/build.gradle` now strips only that
dev-only generated registration before `compileReleaseJavaWithJavac`.

Final result after the build-script fix:

```text
✓ Built build/app/outputs/bundle/release/app-release.aab (61.1MB)
```

Artifact evidence:

- AAB path: `build/app/outputs/bundle/release/app-release.aab`
- AAB size: 58 MiB (`61.1MB` from Flutter)
- AAB SHA-256:
  `c4aab71383a76ffe4385a9aea0717a69e4c76b09ba2be1a185c1807651fd210f`
- AAB signing certificate owner:
  `CN=AMAIA23 Inteligencia Artificial SL, OU=HydraCam, O=AMAIA23 Inteligencia Artificial SL, L=Madrid, ST=Madrid, C=ES`
- AAB signing certificate SHA-256:
  `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`

`bundletool` was available only as a non-executable Gradle library jar, and
`apkanalyzer` expects APK layout rather than AAB layout, so package-name
extraction from the built AAB was not verified with those tools. Source-backed
package configuration remains `applicationId = "com.amaia23.hydracam"` in
`android/app/build.gradle` and `version: 1.4.0+16` in `pubspec.yaml`.

## Next actions

1. Use the Google account that owns the intended AMAIA23 developer account, then
   open Play Console or Android Developer Console and verify/create the
   organization profile.
2. Register package `com.amaia23.hydracam` with SHA-256 fingerprint
   `51:7E:10:AD:DC:7B:EA:CA:0B:FF:90:DD:10:C8:42:95:97:BE:B3:37:F1:A4:91:81:C5:B7:46:E1:D4:7C:5B:C3`.
3. After the AAB builds, upload it to Play internal testing or use the signed
   APK/AAB flow required by Android Developer Console ownership proof.
