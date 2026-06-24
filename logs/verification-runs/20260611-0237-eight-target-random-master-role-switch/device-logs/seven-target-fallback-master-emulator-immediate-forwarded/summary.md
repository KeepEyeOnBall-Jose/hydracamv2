# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `1`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `10.064`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `1` | `8011.106` | `8011.106` | `8011.106` |
| `set_role` | `1` | `592.938` | `592.938` | `592.938` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `1` | `0.786` | `0.786` | `0.786` |
| `requestStartSkewMs` | `1` | `198.257` | `198.257` | `198.257` |
| `requestEndSkewMs` | `1` | `409.407` | `409.407` | `409.407` |
| `maxRequestDurationMs` | `1` | `394.586` | `394.586` | `394.586` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `emulator-5554` | `failed` | `9885e6503930304946`, `RF8M21J8XRT`, `00008101-000A68811E43001E`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos`, `5CF4A12E-A8B5-4285-AE86-407B9067CB5F` | role_switch: Timed out waiting for expected connected slave client remote IPs on emulator-5554: expected=['127.0.0.1', '169.254.13.252', '169.254.193.202'], seen=[], last={'knownClientCount': 0, 'connectedClientCount': 0, 'disconnectedClientCount': 0, 'connectionSummaryLabel': 'No known devices', 'connectedClientIds': [], 'masterServerStartedAt': '2026-06-11T03:49:27.067718', 'connectedClients': [], 'session': {'sessionGuid': None, 'deviceType': 'Unknown', 'isActive': False, 'photoCount': 0, 'videoCount': 0, 'queueLength': 0, 'isUploading': False, 'isRecording': False}} |
