# Store Privacy and Metadata

Last reviewed: 2026-06-09.

This file is the repo-local checklist for App Store privacy labels, Google Play
Data Safety, support URLs, and review notes. It is not a legal policy. Publish a
real public privacy policy before TestFlight external testing or Play release
review, then keep this file aligned with that public policy.

## Required Public URLs

- Privacy Policy URL: not published yet. Publish
  `docs/store/hydracam-privacy-policy.md` after owner/legal review and compile
  it into release builds with `HYDRACAM_PRIVACY_POLICY_URL`.
- Support URL: not published yet. Publish `docs/store/hydracam-support.md`
  after owner review and compile it into release builds with
  `HYDRACAM_SUPPORT_URL`.
- Marketing URL: optional, not published yet.
- Account/data deletion URL: required for the current Auth0 account flow unless
  account creation is disabled in Auth0 and store review accepts that
  configuration. Publish a public HTTPS URL and set
  `HYDRACAM_ACCOUNT_DELETION_URL` before upload. The store build wrapper and
  fastlane lanes pass this value as a Dart define so the in-app pre-login
  account-deletion dialog can open the same public page. Use
  `docs/store/hydracam-account-deletion.md` as the starting draft for that
  public page.

## Data Surface

Declare these store data types unless the code or backend contract changes:

- Photos, videos, and microphone audio: captured locally and may be uploaded to
  the HydraCam/MoBo backend as user content.
- Location: requested when identifying the active recording venue and for Wi-Fi
  SSID access on platforms that gate SSID behind location permission.
- Identifiers: device ID, session GUID, Auth0 identity, app version, and build
  number are used for app functionality, upload correlation, and support.
- Network data: local WebSocket messages expose session/device command state on
  the user's LAN/hotspot; backend calls use HTTPS outside local discovery.
- User-selected gallery media: manually imported media can be attached to
  sessions and uploaded.
- Diagnostics: app logs are stored locally for troubleshooting unless a future
  backend log-upload path is added.

## Store Metadata Inputs

- App name: `HydraCam`.
- iOS bundle ID: `com.keepeyeonball`.
- Android package: `com.amaia23.hydracam`.
- Category: sports / photo-video utility; final category must be chosen in each
  store console.
- Review access: provide demo credentials or a reviewer note explaining how to
  use a local-only session if Auth0 login is not required for the tested flow.
- Review notes: explain that multi-device sync requires devices on the same
  local network or hotspot and uses camera, microphone, local network, gallery,
  and optional location permissions for app functionality.

## Apple Privacy Manifest

`ios/Runner/PrivacyInfo.xcprivacy` is bundled in the Runner target. It declares
current app-functionality data collection for photos/videos, audio, precise
location, email address, user ID, and device ID, with no tracking. It also
declares required-reason API usage for:

- UserDefaults/shared preferences: `CA92.1`.
- File metadata/timestamps inside the app container: `C617.1`.
- Disk-space checks and user-visible low-storage warnings: `E174.1` and
  `85F4.1`.

Keep this file aligned with App Store privacy labels whenever auth, uploads,
diagnostics, storage, or media/session behavior changes.

## Apple Export Compliance

`ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption=false` for the
current app because the repo audit found no custom non-exempt cryptography. The
current app still uses normal platform/network security for Auth0, HTTPS, and
secure credential storage. Revisit this answer before upload if proprietary
encryption, custom cryptography, or a third-party SDK with non-exempt encryption
is added.

## Beta Gate

Do not mark beta submission ready until:

- Privacy Policy and Support URLs are publicly reachable.
- Apple privacy labels and Google Data Safety answers match this data surface.
- App Store Connect app record and Play Console app ownership are confirmed.
- `APP_STORE_CONNECT_API_KEY_PATH` and `GOOGLE_PLAY_JSON_KEY` are configured
  outside the repo or a manual upload owner is assigned.
- `HYDRACAM_ACCOUNT_DELETION_URL` points to a public deletion-request page, and
  the in-app Login screen account-deletion request flow has been smoke-tested
  from a release/Profile build made with that Dart define.
- `HYDRACAM_PRIVACY_POLICY_URL` and `HYDRACAM_SUPPORT_URL` point to public pages,
  and the in-app Login screen policy/support actions have been smoke-tested
  from a release/Profile build made with those Dart defines.
- The final AAB/IPA artifacts have matching `*.store-metadata.tsv` sidecars
  proving they were built with the same public URL Dart defines used for
  submission preflight.
- The pragmatic hardware gate passes: iPhone, iPad, and at least two supported
  Android devices.
