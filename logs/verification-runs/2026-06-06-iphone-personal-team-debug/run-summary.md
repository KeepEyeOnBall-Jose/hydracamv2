# iPhone personal-team debug run

Date: 2026-06-06

Device:
- Jose/Jose Ramon iPhone, UDID `00008101-000A68811E43001E`
- CoreDevice ID `AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A`
- iPhone 12 Pro, iOS 26.4.2

Temporary signing used for this run:
- Team ID `8T78Y2X37H`
- Signing identity `Apple Development: vectorblanco@gmail.com (D3Y6ZN7Z3C)`
- Bundle ID `com.vectorblanco.hydracam.dev`

Commands:
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -destination 'id=00008101-000A68811E43001E' -configuration Debug -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=8T78Y2X37H CODE_SIGN_STYLE=Automatic clean build -quiet`
- `flutter run -d 00008101-000A68811E43001E --debug --no-pub -t lib/main.dart`
- `flutter screenshot -d 00008101-000A68811E43001E -o logs/verification-runs/2026-06-06-iphone-personal-team-debug/iphone-hydracam-debug.png`
- `xcrun devicectl device process terminate --device AB1E2F45-61B1-5FBD-972A-940EA7EC8B0A --pid 77115 --timeout 30`

Results:
- `flutter run` successfully launched and attached to a Dart VM Service at `http://127.0.0.1:51827/kVVWIQlsWro=/`.
- App requested and received camera and microphone permissions.
- App navigated to `SlaveScreen(isAutoMode=true)` and fell back to master mode after no master broadcast was found.
- WebSocket server started on port 4040.
- M2M token was obtained.
- Session was created successfully: ID `466`, GUID `f60e4a7a-ec8e-4897-8943-43dc0325e2d6`.
- A photo was captured, saved under the app documents session folder, saved to gallery, added to the upload queue, and uploaded successfully.
- Video recording was started from master mode.
- The debug process was terminated after the recording-start log to avoid leaving the phone recording.

Limitations:
- `flutter screenshot` reported: `Screenshot not supported for Jose Ramon's iPhone.`
- The org team `4RRY2QT7H8` remains unusable for new iPhone debug signing while the paid membership/certificate state is expired; this run used the personal team as a local debug workaround.
