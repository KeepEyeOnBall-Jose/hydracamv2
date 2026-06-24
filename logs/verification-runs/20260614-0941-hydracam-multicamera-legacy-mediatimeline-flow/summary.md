# Evidence Run: HydraCam multi-camera upload to legacy and media-timeline processing proof

- Source: user goal 2026-06-14
- Slug: `hydracam-multicamera-legacy-mediatimeline-flow`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Create a small accessible test-set folder with one few-second video per camera
- [x] Upload the test clips through the HydraCam legacy upload-media contract into a backend session
- [x] Verify media-timeline imports the legacy session into a new event
- [x] Verify media-timeline processing status reaches complete or document the exact blocked stage

## Test Set

- Accessible copy: `/Users/jose/Desktop/hydracam-multicamera-test-set-20260614-0941/`
- Evidence copy: `video/test-set/`
- Clips:
  - `camera-1-right-corner-20251220_171028-3s.mp4` (3.033s, 65,347 bytes)
  - `camera-2-left-corner-20251220_171059-3s.mp4` (3.066s, 108,082 bytes)
  - `camera-3-center-IMG_2927-3s.mp4` (3.000s, 86,782 bytes)

## Legacy Upload

- Legacy session id: `489`
- Legacy session GUID: `3714fab8-b2de-44cb-a5cd-16df61baec44`
- Legacy details URL: `https://hydracam.azurewebsites.net/HydraCam/Details/489`
- Upload result: `device-logs/legacy-upload-result.json`
- Detail-page proof: `device-logs/legacy-session-489-details.html`
- Uploaded video DB ids observed on the detail page: `450`, `451`, `452`

## Media-Timeline

- Imported event: `hydracam-489`
- Import manifest: `device-logs/media-timeline-hydra-489-manifest.json`
- Local status proof: `device-logs/media-timeline-hydracam-489-local-status.json`
- Media-timeline video ids:
  - `37cf07f2-52a6-4caa-8b00-8cef22eea330`
  - `ca043f52-a9ec-4b90-b154-2412a25a7e72`
  - `afbed374-715a-4bcd-84e1-3cd137793b41`

## Processing

- Queue enqueue proof: `device-logs/media-timeline-hydracam-489-enqueue-missing.json`
- Initial staged readiness was complete for `audio_graph`.
- Queue-backed pose/racket jobs stayed pending behind older long-running jobs, so the same imported media ids were processed through CV Compute unified pose+racket endpoints.
- Tiny sampled unified proof:
  - Camera 1 job `c53e138a`, 6/90 frames, completed
  - Camera 2 job `980f855d`, 7/91 frames, completed
  - Camera 3 job `fbb5501e`, 6/90 frames, completed
- Full tiny-clip unified proof:
  - Camera 1 job `ea76313b`, 90/90 frames, pose count 135, racket count 8
  - Camera 2 job `b064de73`, 91/91 frames, pose count 173, racket count 27
  - Camera 3 job `0c82b540`, 90/90 frames, pose count 174, racket count 14
- Coverage refresh proof: `device-logs/media-timeline-processing-coverage-refresh-after-full-unified.json`
- Final full readiness proof: `device-logs/media-timeline-hydracam-489-readiness-full-after-full-unified.json`

## Result

- Final disposition: passed. Full readiness for `hydracam-489` is complete for all 3 videos across `pose_estimation`, `racket_tracking`, and `audio_graph`.
