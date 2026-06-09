# Win11 Triple-Platform Proof Wrap-Up

Date: 2026-06-09

Status: aborted by user request before completing the requested all-combinations
master/slave proof.

## Original Objective

Prove HydraCam running on the Win11 host by showing one photo and one short
video captured and uploaded from each of these targets:

- Native Windows
- Native Linux through Ubuntu-22.04 WSL
- Android emulator

Then test every master/slave combination among Windows, Linux, and the Android
emulator. If the shared webcam could not be accessed by all targets at once,
use a fallback such as predefined media or another stream.

## Host Maintenance Completed First

The Win11 host maintenance work was completed before this proof attempt was
aborted:

- Android Studio is on the current stable Quail generation:
  `2026.1.1.8`, installed at
  `C:\Users\jose\AppData\Local\Programs\Android Studio Fixed`.
- `flutter doctor -v` from `E:\work-repos\hydracamv2` reported no issues.
- Android SDK command-line tools were repaired to `sdkmanager` `20.0`.
- Android SDK includes `platforms;android-36`, `build-tools;36.1.0`,
  `platform-tools` `37.0.0`, and emulator `36.6.11`.
- The Windows checkout was moved from `D:\src\work\hydracamv2` to
  `E:\work-repos\hydracamv2`.
- `D:\src\work\hydracamv2` is now a junction to
  `E:\work-repos\hydracamv2` for compatibility with older scripts.
- Post-move `flutter pub get` and `flutter doctor -v` passed from the E: path.

Remote maintenance evidence:
`D:\hydracam-evidence\20260609-0415-win11-android-studio-quail-e-drive-move\`.

Local helper scripts:
`logs/verification-runs/20260609-0415-win11-android-studio-quail-e-drive-move/`.

## Capture And Upload Evidence

Evidence root:
`logs/verification-runs/20260609-0245-win11-triple-platform-webcam-upload-matrix/`.

### Windows Native

Result: passed with the real webcam.

- Target: `windows-native`
- Camera: `USB2.0 HD UVC WebCam`
- Backend session GUID: `c0702171-4766-406c-9080-b7059d6bd7b3`
- Photo:
  `remote/windows-real-after-pub-get/media/camera_desktop_2_49014290942000.jpg`
- Video:
  `remote/windows-real-after-pub-get/media/camera_desktop_video_49014529472100.mp4`
- Upload log count: 2 successful media upload lines, 0 failed upload lines
- Media verification: JPEG `640x480`, 48,535 bytes; MP4, 1,026,647 bytes

### Linux Native In WSL

Result: passed only with fallback media.

WSL Ubuntu-22.04 had no `/dev/video*`, so it could not use the physical webcam
directly during this run. The proof used the documented mock-media fallback.

- Target: `linux-native`
- Photo:
  `remote/linux-mock-media-master/media/mock_1_2026-06-09T02-58-06-284175.jpg`
- Video:
  `remote/linux-mock-media-master/media/mock_2_2026-06-09T02-58-10-693602.mp4`
- Upload log count: 8 successful upload-related lines, 0 failed upload lines
- Media verification: JPEG `640x480`, 48,535 bytes; MP4, 1,026,647 bytes

### Android Emulator

Result: real webcam path was not accepted; fallback media passed.

The emulator was launched with `webcam0` mapped to `USB2.0 HD UVC WebCam`, but
the real-camera capture artifacts pulled from the app-private directory were
0 bytes. The accepted Android evidence uses app-private predefined media.

- Target: `android-emulator`
- Emulator: `HydraCam_API33_x86_64` / `emulator-5554`
- Backend session GUID: `a3121f88-8fe3-46e7-aede-6ce8ef712764`
- Fallback photo:
  `remote/android-emulator-private-mock-media-fallback/media-root-pull/android_private_fallback_photo.jpg`
- Fallback video:
  `remote/android-emulator-private-mock-media-fallback/media-root-pull/android_private_fallback_video.mp4`
- Upload log count: 8 successful upload-related lines, 0 failed upload lines
- Media verification: JPEG `640x480`, 48,535 bytes; MP4, 1,026,647 bytes

## Role Matrix Disposition

Result: aborted before completion.

The first role-matrix attempt was blocked because Linux was using the shared
Windows `.dart_tool/package_config.json`, which pointed at `C:\...` package
paths. A separate WSL checkout at `/home/jose/hydracamv2-linux` fixed the Linux
build issue and the Linux app did start its automation bridge on port `6511`.

The next blocker was harness/network addressing: the Windows-side matrix probe
checked the Linux bridge at `http://127.0.0.1:6511`, but the bridge was inside
WSL and needed to be reached through the WSL IP or another explicit forwarding
path. Before completing that correction and rerunning the full matrix, the user
requested that the mission be aborted and wrapped up.

No current evidence should be read as proving every Windows/Linux/Android
master/slave combination.

## Current Truth

- Windows native capture/upload through the real webcam is proven.
- Linux WSL capture/upload is proven only through mock-media fallback, not the
  physical webcam.
- Android emulator capture/upload is proven only through app-private fallback
  media, not the mapped webcam.
- The all-combinations Windows/Linux/Android role matrix is not proven.
- The immediate harness follow-up would be to use a separate WSL checkout plus
  WSL-reachable bridge addressing, then rerun the matrix from scratch.

## Recommended Next Actions

1. Decide whether desktop/emulator fallback-media proof is acceptable for the
   current product milestone, or whether only real camera input counts.
2. If real Linux camera input matters, install and validate `usbipd-win` or an
   equivalent camera-forwarding path before rerunning WSL capture proof.
3. Fix the role-matrix harness to control the Linux bridge through the WSL IP or
   explicit port forwarding, then rerun all three master rotations.
4. Keep Windows desktop support separate from mobile release claims until the
   role matrix and real-camera constraints are resolved.
