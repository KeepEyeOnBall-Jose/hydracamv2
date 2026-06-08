# Evidence Run: ipad-white-blocked

- Source: operator-report-2026-06-08
- Slug: `ipad-white-blocked`
- Verification tier: A (real-hardware)
- Status: partial

## Acceptance Checks

- [x] Physical iPad white screen/block state is classified with live bridge/device evidence

## Device Matrix

- iPad (5), iPad7,5 / iOS 17.7.11 21H461, Flutter id
  `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, CoreDevice id
  `0A947DBD-A462-5BAA-AB84-17F143D41619`, observed in standby/white state and
  then switched to master through the automation bridge.

## Evidence

- `commands.log` records `git status`, `flutter devices`, `xcrun devicectl
  list devices`, iPad bridge `/healthz`, `/session`, `/settings`, `/logs`,
  display state, the successful `set_role` recovery request, post-switch
  `/healthz`, and `connected_clients`.
- `device-logs/ipad-bridge-logs-after-master-switch.json` captures the iOS
  native trace path under `/var/mobile/...`, the launch into standby, the
  runtime role-switch request, and the WebSocket server start on port 4040.
- Direct screenshot/video capture was unavailable from this shell; marker files
  under `screenshots/` and `video/` record the checked tool paths.

## Result

- Final disposition: partial. The reported white state was not a dead app,
  signing failure, or missing bridge. The app was intentionally running in
  automation standby with only the `set_role` bridge command exposed. The
  standby widget renders a normal app bar plus an empty white body. A bridge
  `set_role` request switched the iPad to master successfully; post-switch
  `/healthz` exposed master commands and logs showed the WebSocket server
  started on port 4040. No direct physical-iOS screenshot/video artifact was
  captured with the current local tooling.
