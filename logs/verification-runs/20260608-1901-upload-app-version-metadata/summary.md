# Evidence Run: Uploaded media includes app version

- Source: docs/control/backlog-import.md#open-rows-from-javi-immediate-backlog-row-111
- Slug: `upload-app-version-metadata`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Upload multipart request includes app version metadata
- [x] Upload multipart request includes app build metadata
- [x] Screenshot and video proof show the metadata contract

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner with mocked package metadata
  and mocked HTTP upload client.

## Evidence

- RED proof: `flutter test --no-pub test/services/hydracam_api_service_test.dart`
  captured a multipart upload request containing only `slaveDeviceId`,
  `captureDate`, and `receivedDate`, then failed because `appVersion` was
  missing.
- GREEN proof: the same focused service test passes after
  `HydraCamApiService.uploadMedia()` adds `appVersion` and `appBuildNumber`
  from `PackageInfo.fromPlatform()`.
- Existing upload metadata fields remain covered by the captured multipart
  request assertion.
- Screenshot: `screenshots/upload_app_version_metadata.png`
- Video: `video/upload_app_version_metadata_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. Media upload requests now include app
  version and build number metadata. Keep related upload metadata work open for
  backend contract acceptance and any additional hardcoded upload fields.
