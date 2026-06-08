# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `3`

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `failed` | `RF8M90QE7LX`, `macos` | role_switch: Timed out waiting for expected connected slave client remote IPs on 29d816ac550b7ece: expected=['192.168.178.159', '192.168.178.160'], seen=[], last={'connectedClientCount': 0, 'connectedClientIds': [], 'connectedClients': [], 'session': {'sessionGuid': None, 'deviceType': 'Unknown', 'isActive': False, 'photoCount': 0, 'videoCount': 0, 'queueLength': 0, 'isUploading': False, 'isRecording': False}} |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX` |  |
