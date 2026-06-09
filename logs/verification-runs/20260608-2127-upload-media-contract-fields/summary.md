# Evidence Run: JAVI row 106: Upload media field contract

- Source: docs/control/backlog-import.md
- Slug: `upload-media-contract-fields`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Upload-media query and multipart field names are centralized in a named contract and uploadMedia uses that contract unchanged for photo and video requests.

## Device Matrix

- HydraCam API unit test runner, macOS host / Flutter test, role
  `upload-contract`, identifier `HydraCamApiService upload media contract`.

## Evidence

- `commands.log`: captured RED failure for missing
  `HydraCamUploadMediaContract`, then GREEN focused API service test run.
- `screenshots/upload_media_contract_fields.png`: rendered proof of the row 106
  contract centralization slice.
- `video/upload_media_contract_fields_proof.mp4`: 4.5-second proof video for
  the same RED / CHANGE / GREEN flow.

## Result

- Final disposition: passed for the bounded row 106 local slice. Keep row 106
  open for backend/API contract coordination and any server-side hardcoded field
  cleanup.
