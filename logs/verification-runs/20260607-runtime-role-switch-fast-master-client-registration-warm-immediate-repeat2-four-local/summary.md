# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `4`

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `macos` |  |
| `macos` | `failed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX` | role_switch: Timed out waiting for expected connected slave client remote IPs on macos: expected=['192.168.178.153', '192.168.178.160', '192.168.178.64'], seen=['192.168.178.153', '192.168.178.64'], last={'connectedClientCount': 2, 'connectedClientIds': ['27e50aac-36e8-44d0-91f7-970bdbc526b5', '87df7992-736e-403b-b803-d80b10efd0b1'], 'connectedClients': [{'deviceId': '27e50aac-36e8-44d0-91f7-970bdbc526b5', 'shortDeviceId': '27e50aac', 'remoteIp': '192.168.178.64', 'networkStatus': 'ready', 'networkStatusLabel': 'Ready', 'lastSeen': '2026-06-07T21:55:36.453101', 'network': {'isWifiActive': True, 'ipAddress': '192.168.178.64', 'ssid': 'FRITZ!Box 6591 Cable TZ', 'bssid': '2c:91:ab:8b:a3:07', 'gatewayIp': '192.168.178.1', 'subnetMask': '255.255.255.0', 'subnetSignature': '192.168.178.0/24', 'source': 'device', 'warnings': []}}, {'deviceId': '87df7992-736e-403b-b803-d80b10efd0b1', 'shortDeviceId': '87df7992', 'remoteIp': '192.168.178.153', 'networkStatus': 'ready', 'networkStatusLabel': 'Ready', 'lastSeen': '2026-06-07T21:55:36.453079', 'network': {'isWifiActive': True, 'ipAddress': '192.168.178.153', 'ssid': 'FRITZ!Box 6591 Cable TZ', 'bssid': '2c:91:ab:8b:a3:07', 'gatewayIp': '192.168.178.1', 'subnetMask': '255.255.255.0', 'subnetSignature': '192.168.178.0/24', 'source': 'device', 'warnings': []}}], 'session': {'sessionGuid': None, 'deviceType': 'Unknown', 'isActive': False, 'photoCount': 0, 'videoCount': 0, 'queueLength': 0, 'isUploading': False, 'isRecording': False}} |
