# HydraCam patch of camera_android_camerax 0.7.5+1

Vendored from pub.dev `camera_android_camerax` 0.7.5+1 (CameraX 1.6.2) and
wired in through `dependency_overrides` in the app `pubspec.yaml`. Upstream
`example/`, `test/`, `pigeons/` and `android/src/test/` are left out.

The camera plugin API has no manual shutter or ISO. The patch only exposes
what the app needs to drive Camera2 itself:

- `HydracamCaptureHooks.java` (new): holds the bound CameraX `Camera` and the
  latest `TotalCaptureResult`.
- `PreviewProxyApi.java`: registers the hook as the Preview session capture
  callback.
- `ProcessCameraProviderProxyApi.java`: records the camera returned by
  `bindToLifecycle` and clears it on `unbindAll`.

The app side lives in
`android/app/src/main/kotlin/com/amaia23/hydracam/ManualExposureController.kt`.

To upgrade: copy the new upstream version over this folder (same subset),
re-apply the three edits marked `HydraCam patch`, and keep the CameraX version
in `android/app/build.gradle` equal to the plugin's `cameraxVersion`.
