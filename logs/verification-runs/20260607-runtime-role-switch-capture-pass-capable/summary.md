# Rotating Master/Slave Matrix

- Status: `failed`
- Shared barrier per rotation: `True`
- Rotation count: `4`

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `failed` | `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos` | rotation: POST /settings failed: timed out |
| `RF8M90QE7LX` | `failed` | `29d816ac550b7ece`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos` | rotation: POST /settings failed: timed out |
| `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | `failed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `macos` | rotation: POST /settings failed: timed out |
| `macos` | `failed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | rotation: POST /settings failed: timed out |
