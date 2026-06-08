# Evidence Run: HCMETA-002

- Source: codex
- Slug: `camera-leveling-all-device-screenshots`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [ ] Merged camera leveling work is committed/pushed, and screenshots show the setup/leveling UI on macOS, iPad/iPhone, and all three Android devices.
  - Partial: physical iPad, macOS, iPhone simulator, and all three connected
    Android devices have setup UI evidence. Physical iPhone remains unavailable
    to Flutter/CoreDevice from this host, and the S7 edge screenshot has a black
    camera preview background even though the level overlay is live.

## Device Matrix

- Android SM G960F / Android 10 API 29 / `29d816ac550b7ece` / setup preview
- Android SM G935F / Android 8 API 26 / `9885e6503930304946` / setup preview
- Android SM G970F / Android 12 API 31 / `RF8M90QE7LX` / setup preview
- iPad (5) / iOS 17.7.11 / `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` / setup preview
- iPhone 16 Plus Simulator / iOS 18.4 / `5CF4A12E-A8B5-4285-AE86-407B9067CB5F` / setup preview
- macOS / macOS 26.4.1 / `macos` / setup preview with mock camera

## Evidence

- `commands.log`: device discovery, Android build/install, iOS simulator build,
  macOS build, physical iPad Profile build/install/launch.
- `screenshots/android-sm-g960f-setup.png`: Android setup UI, red tilt state,
  visible live camera feed.
- `screenshots/android-sm-g970f-setup.png`: Android setup UI, red tilt state,
  visible live camera feed.
- `screenshots/android-sm-g935f-setup.png`: Android setup UI and red tilt state;
  preview background is black on this run.
- `screenshots/ipad-physical-setup-rendered.png`: physical iPad app-rendered
  screenshot captured through the automation bridge and copied out with
  `devicectl`; live camera feed, red tilt state, roll/pitch, and perspective
  selector are visible.
- `screenshots/iphone-16-plus-simulator-setup-attached.png`: iPhone simulator
  setup UI with sensor/camera unavailable state and perspective selector.
- `screenshots/macos-setup-preview-window.png`: macOS setup UI with mock camera
  and sensor-unavailable state.
- `device-logs/ipad-physical-setup-logs.json`: physical iPad logs showing
  setup role, granted camera/mic permissions, camera selection, and successful
  camera initialization.
- `device-logs/ipad-capture-screenshot-response.json`: physical iPad
  automation screenshot response, including app container copy source.

## Result

- Final disposition: partial. The new setup UI and level overlay are visible on
  every currently reachable platform lane, with real camera preview proven on
  iPad, SM G960F, and SM G970F. Remaining gaps are physical iPhone availability
  and the S7 edge black preview retake.
