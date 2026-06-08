# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `8`
- Repeat role-switch cycles: `2`
- Elapsed seconds: `63.919`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `8` | `230.444` | `475.101` | `1198.97` |
| `set_role` | `8` | `137.216` | `399.213` | `1181.741` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `8` | `0.225` | `0.558` | `1.075` |
| `requestStartSkewMs` | `8` | `108.736` | `329.289` | `967.173` |
| `requestEndSkewMs` | `8` | `135.444` | `364.513` | `1069.848` |
| `maxRequestDurationMs` | `8` | `28.587` | `71.567` | `215.106` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `8` | `-278.367` | `172.886` | `758.728` |
| `latestClientRegistrationLagMs` | `8` | `81.049` | `687.322` | `2047.156` |
| `maxClientRegistrationAfterServerStartMs` | `8` | `315.791` | `514.436` | `1337.411` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX` |  |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX` |  |
