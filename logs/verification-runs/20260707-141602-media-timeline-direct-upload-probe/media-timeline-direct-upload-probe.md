# media-timeline direct upload probe: PASS

- API base URL: `http://127.0.0.1:3001/api`
- Checked at: `2026-07-07T14:16:02Z`
- eventId: `hydracam-8737f611-011f-4b3b-9e76-8b165dc023a5`
- sessionGuid: `8737f611-011f-4b3b-9e76-8b165dc023a5`
- fileId: `b55694dc-dd18-45ed-b1fd-fa7d9d68c01f`
- locator: `s3://media-timeline/events/hydracam-8737f611-011f-4b3b-9e76-8b165dc023a5/2026-07-07T14-16-02-245Z-hydracam-direct-upload-probe-5888e5e7-b684-4887-a971-4ab9ba1db57f.jpg`

| Step | Status |
| --- | --- |
| `createBridgeSession` | `ok` |
| `startBridgeDirectUpload` | `ok` |
| `startMediaStorageMultipartUpload` | `ok` |
| `uploadMediaStorageMultipartPart` | `ok` |
| `completeMediaStorageMultipartUpload` | `ok` |
| `completeBridgeUpload` | `ok` |
| `readBridgeSessionStatus` | `ok` |
