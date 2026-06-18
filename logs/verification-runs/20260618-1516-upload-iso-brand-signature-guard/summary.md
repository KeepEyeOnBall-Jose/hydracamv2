# Upload ISO Brand Signature Guard

- Status: `passed`
- Date: `2026-06-18`
- Control-plane item: `docs/control/backlog-import.md` T-016, `Photo/video upload API test with invalid files`
- Scope: local media signature validation before upload.

## What Changed

- Tightened ISO BMFF validation so `ftyp` at bytes 4-7 is accepted only when
  the major brand is in the expected photo or video brand set.
- Rejected forged unsupported ISO video signatures before token lookup or HTTP
  upload.
- Added a HEIC-style photo fixture to prove supported iOS photo media still
  uploads through the existing multipart path.

## Validation

```bash
flutter test --no-pub test/services/hydracam_api_service_test.dart --plain-name 'uploadMedia rejects unsupported ISO media signatures before HTTP send'
flutter test --no-pub test/services/hydracam_api_service_test.dart --plain-name 'uploadMedia accepts supported HEIC photo signatures'
flutter test --no-pub test/services/hydracam_api_service_test.dart
flutter analyze --no-pub lib/services/hydracam_api_service.dart test/services/hydracam_api_service_test.dart
flutter test --no-pub
flutter analyze --no-pub
```

All commands passed.

## Notes

- This is a local upload validation guard; no device or backend credentials are
  required for the mocked media-signature regression.
