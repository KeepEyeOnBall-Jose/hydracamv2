# Evidence Run: Verify and provision the reachable HydraCam fleet onto one LAN

- Source: docs/control/status-and-roadmap.md#current-mobile-status
- Slug: `astral-express-fleet-wifi`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] A project-local cleartext credential file contains JuJo and Astral Express without printing passwords into evidence logs
- [x] Every authorized attached Android phone stores both Wi-Fi profiles and associates to Astral Express
- [x] Every reachable Apple device is either associated to Astral Express or has an exact platform blocker recorded

## Device Matrix

- Samsung Galaxy S9 / Android 10 / `29d816ac550b7ece`: both networks stored;
  connected to `Astral Express` at `192.168.178.134`.
- Samsung Galaxy S7 edge / Android 8 / `9885e6503930304946`: both networks
  stored; connected to `Astral Express` at `192.168.178.131`.
- Samsung Galaxy S10e / Android 12 / `RF8M2125DAJ`: both networks stored;
  connected to `Astral Express` at `192.168.178.129`.
- Samsung Galaxy S10e / Android 12 / `RF8M40MT6AW`: both networks stored;
  connected to `Astral Express` at `192.168.178.130`.
- Samsung Galaxy S10e / Android 12 / `RF8M90QE7LX`: both networks stored;
  connected to `Astral Express` at `192.168.178.132`.
- iPhone 12 Pro / iOS 26.5.2 /
  `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`: profile download returned HTTP 200;
  manual Install approval remains unconfirmed.
- iPad 6th generation / iPadOS /
  `0A947DBD-A462-5BAA-AB84-17F143D41619`: profile download returned HTTP 200
  over the USB link-local network; manual Install approval remains unconfirmed.

## Evidence

- `commands.log`: passing Android helper tests and five-device subnet preflight.
- `device-logs/fleet-ssid-summary.txt`: exact SSID evidence for all five Android
  devices.
- `device-logs/s7-s9-saved-networks.txt`: configured-network evidence for both
  requested SSIDs on the two Android versions that restrict shell Wi-Fi commands.
- `device-logs/apple-profile-delivery.txt`: redacted iPhone/iPad profile delivery
  evidence and the unsupervised-iOS approval boundary.
- Local-only `screenshots/`: Android Wi-Fi settings proof for the five connected
  devices; repo policy intentionally ignores these generated PNGs.
- Local-only `video/29d816ac550b7ece-astral-express.mp4`: physical S9 Wi-Fi
  settings recording; repo policy intentionally ignores generated video.
- Exact-secret scan across the tracked diff and evidence pack found zero
  credential matches.

## Result

- Final disposition: partial. All five ADB-visible Android phones are complete.
  The Apple profiles were delivered but installation needs user confirmation.
  The POCO and iPhone 11 were not data-visible; the user's main S10e was
  intentionally excluded.
