# Evidence Run: Avoid zero ETA during active upload

- Source: docs/control/backlog-import.md#4-improve-upload-failure-cancel-requeue-and-progress-ui
- Slug: `uploader-active-upload-zero-eta-label`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Uploader summary does not show Estimated remaining: 0s while a current upload is active
- [x] Uploader summary still shows zero remaining when no upload is active and the queue is empty

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded a red focused `UploaderInfoScreen` widget test showing active
  upload state still displayed `Estimated remaining: 0s`, then reran the
  focused screen file, `flutter test --no-pub test/screens`,
  `flutter analyze --no-pub`, `git diff --check`, and full
  `flutter test --no-pub`.

## Result

- Final disposition: passed
