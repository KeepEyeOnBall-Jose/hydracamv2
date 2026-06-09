# HydraCam Support Draft

Last updated: 2026-06-09.

This draft is prepared for the store Support URL. It must be reviewed and
published at a public URL before external beta or production review.

## What HydraCam Does

HydraCam coordinates photo and video capture across nearby phones and tablets
for sports sessions. One device acts as the master and nearby devices can act as
slaves on the same local network or hotspot.

## Setup Checklist

- Install HydraCam on each device.
- Keep devices unlocked and on the same Wi-Fi network or hotspot.
- Grant camera and microphone access.
- Grant local network access on iOS.
- Grant location access when the platform requires it for Wi-Fi/SSID discovery
  or venue tagging.
- Confirm each device has enough storage and battery before recording.

## Troubleshooting

- If devices do not see each other, verify they are on the same local network or
  hotspot and that local network permissions are enabled.
- If capture fails, close other camera apps and reopen HydraCam.
- If upload does not start, check network connectivity and use the uploader
  status screen to retry queued or failed items.
- If iOS shows an old duplicate HydraCam icon during beta testing, remove the
  older app before installing the current TestFlight build.

## Account And Data Deletion

Use the in-app Login screen action named "Request Account Deletion" to prepare a
request with the login email and HydraCam GUID. Release builds configured with
the published deletion URL can also open that page directly from the same
dialog. Use `docs/store/hydracam-account-deletion.md` as the deletion-page
draft. The published support page must provide the final submission form or
support contact for deleting Auth0 account data, HydraCam backend user records,
uploaded session media, and related diagnostics after a verified request.

## Contact

Support email or contact form: to be published before submission.
