# Evidence Run: Auth allowlist dashboard and development-device login

- Source: user-request: connected devices and allowed upload users
- Slug: `auth-allowlist-dashboard-dev-login`
- Verification tier: mixed dashboard/API plus connected Android emulator device proof
- Status: passed for currently responsive development targets; physical iOS devices were present but unavailable

## Acceptance Checks

- [x] Connected device inventory is captured from the live dashboard API
- [x] Allowed upload users include vectorblanco@gmail.com, jose@keepeyeonball.com, and pkosiak@gmail.com
- [x] Development auto-login path has focused unit coverage and is compile-time gated
- [x] Same-turn Android emulator launch proof for development auto-login

## Device Matrix

- sdk gphone64 arm64, Android emulator, `emulator-5554`, connected development auto-login/upload target
- iPhone 16 Pro, iOS 18.4 simulator, `6A2E7E6A-05F8-47D6-88AE-85E3434AC6D3`, connected development auto-login/upload target
- macOS, macOS 26.4.1, `macos`, connected controller/mock-camera development target
- Chrome, `chrome`, connected dashboard validation target
- Jose Ramon's iPhone, iPhone 12 Pro / CoreDevice unavailable, `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`, paired unavailable physical upload target
- iPad (5), iPad 6th generation / CoreDevice unavailable, `0A947DBD-A462-5BAA-AB84-17F143D41619`, paired unavailable physical upload target

## Evidence

- `device-logs/hydracam-admin-access.json` records the current proxied dashboard API response.
- `screenshots/hydracam-admin-dashboard.png` shows the rendered media-timeline dashboard with the seeded users and current devices.
- `video/` contains the dashboard reload proof captured by Playwright.
- `../20260622-1925-android-emulator-dev-auto-login-smoke/summary.json` records the debug APK build with `HYDRACAM_DEV_AUTO_LOGIN=true` and `HYDRACAM_DEV_AUTO_LOGIN_EMAIL=jose@keepeyeonball.com`.
- `../20260622-1925-android-emulator-dev-auto-login-smoke/device-logs/emulator-5554/standby-bridge-logs.json` contains the runtime log `Development auto-login restored user jose@keepeyeonball.com.`

## Result

- Final disposition: passed for the requested auth allowlist, backend dashboard, live responsive device inventory, and automatic development login smoke on `emulator-5554`. The physical iPhone and iPad remain unavailable in CoreDevice, so they are listed but not enabled for development login/upload until unlocked/reconnected.
