# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `2`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `16.449`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `2` | `8009.049` | `8029.429` | `8049.809` |
| `set_role` | `2` | `46.067` | `55.923` | `65.779` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `2` | `0.0` | `0.0` | `0.0` |
| `requestStartSkewMs` | `2` | `20.002` | `39.852` | `59.703` |
| `requestEndSkewMs` | `2` | `25.01` | `26.821` | `28.632` |
| `maxRequestDurationMs` | `2` | `25.916` | `33.242` | `40.568` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `00008101-000A68811E43001E` | `failed` | `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | role_switch: Timed out waiting for expected connected slave client remote IPs on 00008101-000A68811E43001E: expected=['192.168.178.104'], seen=[], last={'knownClientCount': 0, 'connectedClientCount': 0, 'disconnectedClientCount': 0, 'connectionSummaryLabel': 'No known devices', 'connectedClientIds': [], 'masterServerStartedAt': '2026-06-09T09:20:50.125279', 'connectedClients': [], 'session': {'sessionGuid': None, 'deviceType': 'Unknown', 'isActive': False, 'photoCount': 0, 'videoCount': 0, 'queueLength': 0, 'isUploading': False, 'isRecording': False}} |
| `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | `failed` | `00008101-000A68811E43001E` | role_switch: Timed out waiting for expected connected slave client remote IPs on 8b406aa5c597eab4c4dfd9908f4a09b10a89ec63: expected=['169.254.99.102'], seen=['192.168.178.168'], last={'knownClientCount': 1, 'connectedClientCount': 1, 'disconnectedClientCount': 0, 'connectionSummaryLabel': '1 connected · 0 disconnected', 'connectedClientIds': ['a6864314-aa27-4e0a-9be4-a38fcbff1b93'], 'masterServerStartedAt': '2026-06-09T09:20:58.364398', 'connectedClients': [{'deviceId': 'a6864314-aa27-4e0a-9be4-a38fcbff1b93', 'shortDeviceId': 'a6864314', 'isConnected': True, 'connectionStatusLabel': 'Connected', 'remoteIp': '192.168.178.168', 'networkStatus': 'ready', 'networkStatusLabel': 'Ready', 'previewStatus': 'unavailable', 'previewStatusLabel': 'Preview unavailable', 'previewTransportLabel': 'Preview transport not configured', 'reportedSessionGuid': None, 'sessionStatus': 'unknown', 'sessionStatusLabel': 'Session not reported', 'identifyStatus': 'notRequested', 'identifyStatusLabel': 'Identify not requested', 'lastIdentifyRequestId': None, 'lastIdentifyRequestedAt': None, 'lastIdentifyAckAt': None, 'registeredAt': '2026-06-09T09:20:58.509674', 'lastSeen': '2026-06-09T09:21:03.572763', 'disconnectedAt': None, 'network': {'isWifiActive': True, 'ipAddress': '192.168.178.168', 'ssid': None, 'bssid': None, 'gatewayIp': '192.168.178.1', 'subnetMask': '255.255.255.0', 'subnetSignature': '192.168.178.0/24', 'source': 'device', 'warnings': ['SSID unavailable; grant location permission and enable Location Services.']}, 'setupStatus': {'cameraPerspectiveId': 'unknown', 'cameraPerspectiveLabel': 'Unknown', 'isLevel': False, 'sensorAvailable': True, 'rollDegrees': 99.22275470591653, 'pitchDegrees': -90.99319407595398}}], 'session': {'sessionGuid': None, 'deviceType': 'Unknown', 'isActive': False, 'photoCount': 0, 'videoCount': 0, 'queueLength': 0, 'isUploading': False, 'isRecording': False}} |
