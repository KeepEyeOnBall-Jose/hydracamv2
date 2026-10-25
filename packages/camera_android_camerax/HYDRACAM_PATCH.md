# HydraCam patch of camera_android_camerax 0.7.5+1

Vendored from pub.dev `camera_android_camerax` 0.7.5+1 (CameraX 1.6.2) and
wired in through `dependency_overrides` in the app `pubspec.yaml`. Upstream
`example/`, `test/`, `pigeons/` and `android/src/test/` are left out.

The camera plugin API has no manual shutter or ISO. The patch only exposes
what the app needs to drive Camera2 itself:

- `HydracamCaptureHooks.java` (new): keeps the bound CameraX `Camera`, registered
  Preview observer and configured Camera2 session together. Results from retired
  sessions, unbound Previews or another camera are rejected. Expected-camera
  lookup is atomic with binding/result publication.
- `PreviewProxyApi.java`: registers capture and session-state callbacks for each
  Preview. Retained Preview observers survive analysis/video graph transitions.
- `ProcessCameraProviderProxyApi.java`: invalidates the prior result before graph
  changes, records bindings and removes only the explicitly unbound Previews.
  Full unbind clears the camera/session/result tuple.

The app side lives in
`android/app/src/main/kotlin/com/amaia23/hydracam/ManualExposureController.kt`.
Both ISO/focus metering and recorded metadata use expected-camera lookup.
Its exposure lease retains the original owner/control/options until restoration
is acknowledged; another binding cannot silently inherit that lease.

The local native regression tests are under `android/src/test/`; upstream's
test tree remains omitted. Unit protocol results do not establish live sensor
or whole-clip exposure acceptance.

To upgrade: copy the new upstream version over this folder (same subset),
re-apply the three edits marked `HydraCam patch`, and keep the CameraX version
in `android/app/build.gradle` equal to the plugin's `cameraxVersion`.
