# Evidence Run: Update Android hardware installs and run all-hardware iOS/Android role-switch test

- Source: docs/control/status-and-roadmap.md
- Slug: `all-hardware-ios-android-update-role-test`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] All visible supported Android hardware is updated with the current automation-enabled HydraCam APK or records a device-specific install blocker.
- [x] The physical iPhone and iPad remain reachable on identity-matched automation bridges at port 4762.
- [x] All included hardware devices expose warm bridges and complete a selected-set role-switch proof, or every excluded hardware device has a concrete blocker.
- [x] The run captures device inventory, install/version evidence, bridge health, screenshots or screenshot blockers, and logs.

## Device Matrix

- SM G960F / Android 10 API 29 / `29d816ac550b7ece`: APK updated; included in six-device role-switch proof.
- SM G935F / Android 8.0 API 26 / `9885e6503930304946`: APK updated; included in six-device role-switch proof with known `s7_exynos_camera_timeout` capture blocker.
- SM G970F / Android 12 API 31 / `RF8M21J8XRT`: APK updated; included in six-device role-switch proof.
- SM G970F / Android 12 API 31 / `RF8M90QE7LX`: APK updated; included in six-device role-switch proof.
- 2201116PG / Android 13 API 33 / `575ecf2cbd24`: Wi-Fi ready, but APK update blocked by `INSTALL_FAILED_USER_RESTRICTED`; excluded from current-build role-switch proof.
- José Ramón's iPhone / iOS 26.5 / `00008101-000A68811E43001E`: bridge healthy at `192.168.178.168:4762`; included in six-device role-switch proof.
- iPad (5) / iOS 17.7.11 / `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`: bridge healthy at `192.168.178.104:4762`; included in six-device role-switch proof.

## Evidence

- `device-logs/six-device-current-build-role-switch/summary.md`: passed six role rotations in `43.435s`.
- `screenshots/`: six foreground screenshots copied from the included devices.
- `video/android-RF8M21J8XRT-six-device-foreground.mp4`: short Android foreground screen recording.
- `commands.log`: device inventory, APK build, install/version checks, Wi-Fi preflight, iOS bridge health, screenshot copy, and cleanup commands.

## Result

- Final disposition: partial. Four Samsung Android devices were updated to the current APK and the six-device current-build iOS/Android role-switch proof passed. The visible Xiaomi 2201116PG remains blocked by device-side `INSTALL_FAILED_USER_RESTRICTED`, so the literal seven-device hardware set was not fully updated or included.
