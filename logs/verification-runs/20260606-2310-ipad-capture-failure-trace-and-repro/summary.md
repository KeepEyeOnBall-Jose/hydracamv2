# Evidence Run: iPad capture failure trace and repro

- Source: user goal 2026-06-06 iPad capture failure
- Slug: `ipad-capture-failure-trace-and-repro`
- Verification tier: A (real-hardware)
- Status: passed

## Acceptance Checks

- [x] iPad run produces trace logs for photo and recording failures
- [x] Mechanical repro script can drive local session photo start stop recording
- [x] Analyzer and Flutter tests pass after the fix

## Device Matrix

- iPad (5), iOS 15.6.1 19G82, Flutter device id
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, physical iOS target.
  Final validation ran over USB with the automation bridge reachable at
  `http://192.168.178.104:4762`.

## Evidence

- `commands.log` records `flutter devices`, `xcrun xctrace list devices`,
  `which iproxy`, `scripts/ios_capture_repro.py --help`,
  `flutter analyze --no-pub`, `flutter test --no-pub
  test/services/camera_service_failure_test.dart`, `git diff --check`, and
  `flutter test --no-pub`.
- Dependency evidence shows Flutter 3.44.1 stable, `camera` upgraded from
  `0.11.2+1` to `0.11.4`, and `camera_avfoundation` upgraded from
  `0.9.21+2` to `0.9.23+2` within the existing `0.11.x` camera line.
- A bounded direct `flutter run -d
  8b406aa5c597eab4c4dfd9908f4a09b10a89ec63 --debug --no-pub
  --dart-define=HYDRACAM_AUTOMATION=true -t lib/main.dart` built with Xcode
  in 24.1s, then failed during wireless install/launch attach after 132.7s.
  Flutter reported that the Dart VM Service was not discovered and advised
  allowing local-network device discovery on the iPad. `iproxy` and
  `ideviceinfo` are not installed, so USB port-forward verification of the
  automation bridge was unavailable.
- `device-logs/ipad-usb-automation-repro/flutter-run.log` captured the
  original iPad failure: `CameraException(setFlashModeFailed, Device does not
  have flash capabilities)` during `CameraService.ensureCameraIsReady()`.
- `device-logs/ipad-usb-automation-repro-3/summary.json` passed on physical
  iPad after the fix. `automation-snapshots.json` shows `photoCount=1` after
  `take_photo`, `isRecording=true` after `start_recording`, and `videoCount=1`
  with `isRecording=false` after `stop_recording`.
- The final persisted trace path was
  `/var/mobile/Containers/Data/Application/209DF7CB-AD67-41F1-8B89-3DED2795BD48/Documents/logs/hydracam-trace-2026-06-06T23-51-42-078995.ndjson`;
  validation parsed 59 persisted NDJSON lines with 0 malformed lines.
- `test/screens/master_video_recording_screen_test.dart` verifies the recording
  preview exits through the close button when no recording is active and no
  camera controller exists, without calling stop recording.

## Result

- Final disposition: passed. The iPad no-flash camera initialization failure is
  fixed, the app captured one photo and one video on the physical iPad, the
  recording state returned to false after stop, the preview has an escape path
  when recording is inactive, and the trace/repro path is mechanically
  repeatable.
