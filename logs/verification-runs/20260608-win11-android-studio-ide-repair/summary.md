# Win11 Android Studio IDE Repair

Date: 2026-06-08

Host: `DESKTOP-02NDERS` / `100.110.8.112`

## Problem

The normal Android Studio launcher at
`C:\Program Files\Android\Android Studio\bin\studio64.exe` failed before IDE
startup. The active `AndroidStudio2025.3.1` log showed a duplicate IntelliLang
plugin registration and `Start Failed`, so the prior Win11 readiness claim only
covered CLI Android/Flutter work, not Android Studio.

## Repair

- Kept the working user-local install:
  `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed`.
- Removed stale application trees:
  - `C:\Program Files\Android\Android Studio`
  - `C:\Program Files\Android\Android Studio1`
  - `C:\Program Files\Android\Android Studio2`
- Removed old Studio config/cache trees for `AndroidStudio2021.3`,
  `AndroidStudio2022.1`, and `AndroidStudio2025.3.1`.
- Left Android SDK, AVDs, Flutter, Gradle, WSL, and project checkouts in place.
- Repointed Start Menu/Desktop shortcuts and the Windows uninstall registry
  entry to the working install.

The removed IDE files totaled about `10.57 GiB`. A post-cleanup drive check
reported `C:` at `70.57 GiB` free and `D:` at `1749.15 GiB` free.

## Verification

- Only remaining `studio64.exe`:
  `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed\bin\studio64.exe`.
- `flutter doctor -v` on Windows resolves Android Java to:
  `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed\jbr\bin\java`.
- `studio64.exe D:\src\work\hydracamv2` stayed alive during a 45-second
  process/log smoke.
- Fresh `AndroidStudio2025.3.3\log\idea.log` accepted the HydraCam project path
  and had zero lines matching:
  `Start Failed`, `Duplicate registration`, `PluginException`, `SEVERE`, or
  `Internal error`.
- A follow-up interactive scheduled-task launch started the fixed IDE for the
  active RDP session as PID `2972`. The temporary task and wrapper script were
  deleted after launch.

## Remaining UI Check

The final human-visible check is to confirm the Android Studio window is visible
in the active RDP session and run one IDE-side emulator/build smoke from
`D:\src\work\hydracamv2`.
