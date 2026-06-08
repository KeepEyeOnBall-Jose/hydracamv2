# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `5`

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`, `macos` |  |
| `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
