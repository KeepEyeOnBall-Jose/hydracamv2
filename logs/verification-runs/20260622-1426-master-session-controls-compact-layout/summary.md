# Evidence Run: master session controls compact layout

- Source: user request 2026-06-22 unify Session information and buttons panel to reduce wasted space and overflow
- Slug: `master-session-controls-compact-layout`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] Session information and controls share one panel on the Master main page
- [x] Active-session controls wrap without overflow on compact portrait and landscape viewports
- [x] Relevant Flutter tests and analyzer pass
- [x] Connected hardware smoke is attempted or explicit blocker is recorded

## Device Matrix

- Samsung SM-G935F / Android 8.0.0 / `9885e6503930304946` / Master page
  portrait smoke through `joss-macbook-air.tail6ce139.ts.net`.
- Samsung SM-G970F / Android 12 / `RF8M90QE7LX` / Master page landscape smoke
  through `joss-macbook-air.tail6ce139.ts.net`.

## Evidence

- Flutter widget tests:
  `flutter test test/widgets/session_info_widget_test.dart test/master/master_screen_test.dart`
  passed, including the new compact portrait/landscape active-session panel
  regression test.
- Static analysis: `flutter analyze` passed.
- Android build: `flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true`
  passed.
- MBA13 hardware smoke installed the APK on both attached Android phones,
  launched `MasterScreen`, captured automation screenshots and screenrecords,
  and copied bridge health/logcat evidence.
- Screenshot evidence:
  `screenshots/master-compact-9885e6503930304946.png`,
  `screenshots/master-compact-RF8M90QE7LX.png`.
- Video evidence:
  `video/master-compact-9885e6503930304946.mp4`,
  `video/master-compact-RF8M90QE7LX.mp4`.
- Local evidence validator:
  `device-logs/validate_master_ui_evidence.py` confirmed screenshots, videos,
  bridge commands, installs, and no Flutter overflow markers in logcat.

## Result

- Final disposition: passed. Note: one late wrapper retry hit transient SSH
  `Can't assign requested address`; the successful device artifacts were
  already copied and validated locally.
