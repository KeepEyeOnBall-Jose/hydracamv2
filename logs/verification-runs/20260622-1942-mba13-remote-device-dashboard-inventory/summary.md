# Evidence Run: MBA13 remote device dashboard inventory

- Source: user-request: iPhone and iPad are attached to MBA13 over Tailscale
- Slug: `mba13-remote-device-dashboard-inventory`
- Verification tier: B/C mixed remote host and connected-device inventory
- Status: passed

## Checks

- [x] Reached MBA13 over Tailscale SSH as `jose`
- [x] Directly inventoried MBA13 Android devices with `adb devices -l`
- [x] Directly inventoried MBA13 iOS devices with `xcrun devicectl list devices`
- [x] Updated media-timeline HydraCam Admin inventory to include SSH-backed remote hosts
- [x] Set local backend `.env` to `HYDRACAM_REMOTE_DEVICE_HOSTS=mba13`
- [x] Verified the live proxied dashboard API reports the remote iPhone/iPad as connected
- [x] Verified the rendered dashboard shows the remote devices with no browser console warnings/errors

## Remote Device Matrix

- `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, Jose Ramon's iPhone, iPhone 12 Pro, CoreDevice `available (paired)`, via `mba13`
- `0A947DBD-A462-5BAA-AB84-17F143D41619`, iPad (5), iPad 6th generation, CoreDevice `available (paired)`, via `mba13`
- `9885e6503930304946`, Samsung S7 edge / SM-G935F, ADB connected, via `mba13`
- `RF8M21J8XRT`, Samsung S10e / SM-G970F, ADB connected, via `mba13`
- `RF8M90QE7LX`, Samsung S10e / SM-G970F, ADB connected, via `mba13`

## Evidence

- `device-logs/mba13-adb-devices.txt`
- `device-logs/mba13-coredevice-devices.txt`
- `device-logs/hydracam-admin-remote-access.json`
- `screenshots/hydracam-admin-mba13-remote-devices.png`

## Result

The local media-timeline HydraCam Admin dashboard can now continue from MBA13-attached development devices through Tailscale SSH inventory. The iPhone and iPad are no longer shown as unavailable when `HYDRACAM_REMOTE_DEVICE_HOSTS=mba13` is loaded by the backend.
