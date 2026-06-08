# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `2`

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `RF8M90QE7LX` | `failed` | `macos` | Command set_role was not registered: POST /commands/set_role failed: HTTP 404: {"error":"unknown_command","command":"set_role"} |
| `macos` | `failed` | `RF8M90QE7LX` | Command set_role was not registered: POST /commands/set_role failed: HTTP 404: {"error":"unknown_command","command":"set_role"} |
