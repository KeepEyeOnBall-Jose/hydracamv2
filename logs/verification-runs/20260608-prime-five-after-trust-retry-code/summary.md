# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `5`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `2.01`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `5` | `221.886` | `235.541` | `255.561` |
| `set_role` | `5` | `69.265` | `158.652` | `195.614` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `5` | `0.391` | `2.613` | `7.855` |
| `requestStartSkewMs` | `5` | `18.668` | `120.827` | `168.122` |
| `requestEndSkewMs` | `5` | `38.943` | `75.54` | `152.183` |
| `maxRequestDurationMs` | `5` | `36.756` | `89.623` | `156.476` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `5` | `-340.008` | `70.108` | `456.658` |
| `latestClientRegistrationLagMs` | `5` | `-100.169` | `351.288` | `830.535` |
| `maxClientRegistrationAfterServerStartMs` | `5` | `239.839` | `281.18` | `373.877` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
