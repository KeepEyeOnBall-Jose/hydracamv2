# HydraCam Privacy Policy Draft

Last updated: 2026-06-09.

This draft is prepared for the HydraCam App Store and Google Play submission
flow. It must be reviewed by the app owner and published at a public,
non-PDF URL before external TestFlight, Google Play testing, or production
review.

## App

HydraCam is a mobile application for synchronized sports-event photo and video
capture across nearby devices.

## Data We Collect Or Process

- Account data: Auth0 login identity, such as email or profile information
  returned by the identity provider.
- Device and session identifiers: device ID, session GUID, app version, build
  number, and local network role state used to coordinate capture and support
  troubleshooting.
- Media content: photos, videos, microphone audio, and user-selected gallery
  media captured or attached by the user.
- Location and network context: optional venue/location data and Wi-Fi/network
  information needed for local device discovery on platforms that require
  location permission for SSID access.
- Diagnostics: app logs generated locally to diagnose capture, upload, network,
  storage, battery, and permission issues.

## How We Use Data

HydraCam uses this data to create and manage recording sessions, coordinate
master/slave device capture on a local network or hotspot, save media locally,
upload selected session media to the configured HydraCam/MoBo backend, restore
signed-in sessions, and diagnose user-reported problems.

## Sharing And Storage

Media and session metadata may be uploaded to the configured HydraCam/MoBo
backend when upload is enabled or manually requested. Local WebSocket messages
are exchanged only between nearby devices on the same local network or hotspot.
Authentication is handled through Auth0. HydraCam does not use this data for
third-party advertising in the current release.

## Retention And Deletion

Session media remains on the device unless the user deletes it or enables a
delete-after-upload setting. Uploaded backend media and account-linked data must
be deleted through the published support or deletion process for the production
service. The public policy must name the operational contact and retention
timelines before submission.

## Account And Data Deletion

HydraCam includes an in-app account-deletion request path on the login/account
screen. Release builds configured with the published deletion URL can open that
page directly from the same dialog. Use
`docs/store/hydracam-account-deletion.md` as the draft for the same
account-deletion request page used in App Store Connect and Google Play Data
Safety. The published production policy must explain how Auth0 account data,
HydraCam backend user records, uploaded session media, and diagnostic data are
deleted or retained after a verified request.

## Security

HydraCam uses HTTPS for backend API calls outside local discovery and stores
Auth0 credentials using secure platform storage. Local device synchronization
uses WebSockets on the user's trusted local network or hotspot.

## Contact

Support and privacy contact: to be published before submission.
