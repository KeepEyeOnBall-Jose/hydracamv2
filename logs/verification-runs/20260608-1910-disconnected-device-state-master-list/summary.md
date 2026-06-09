# Evidence Run: Disconnected device state in master list

- Source: docs/control/backlog-import.md#6-make-network-device-identity-visible
- Slug: `disconnected-device-state-master-list`
- Verification tier: D (integration-unit-tests)
- Status: partial

## Acceptance Checks

- [x] Master retains a disconnected device record after socket removal
- [x] Connected device IDs still include only live sockets
- [x] Master UI/status proof distinguishes disconnected devices

## Device Matrix

- `flutter-test`: macOS Flutter unit-test runner with mocked master WebSocket
  registrations and socket removals.

## Evidence

- RED proof: `flutter test --no-pub test/master/master_network_snapshot_cache_test.dart`
  failed to compile because `ConnectedDeviceInfo` had no `isConnected`,
  `connectionStatusLabel`, or `disconnectedAt` state.
- GREEN proof: the focused master-server test passes after retaining
  disconnected client diagnostics while `getConnectedDeviceIds()` remains
  live-socket-only.
- Automation payload proof:
  `flutter test --no-pub test/master/connected_client_automation_payload_test.dart`
  verifies disconnected diagnostics remain visible without inflating
  `connectedClientCount` or `connectedClientIds`.
- Screenshot: `screenshots/disconnected_device_state_master_list.png`
- Video: `video/disconnected_device_state_master_list_proof.mp4`
- Device/test log: `device-logs/flutter-test-runner.log`
- Commands: `commands.log`

## Result

- Final disposition: partially completed. The master device list can now
  distinguish a known disconnected slave from currently connected sockets.
  Keep item 6 open for broader master-list UX refinements and real-device
  validation.
