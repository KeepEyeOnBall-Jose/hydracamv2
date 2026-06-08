# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `5`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `1.886`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `5` | `114.19` | `190.244` | `219.286` |
| `set_role` | `5` | `56.516` | `179.226` | `291.134` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `5` | `0.42` | `0.512` | `0.566` |
| `requestStartSkewMs` | `5` | `19.226` | `119.507` | `172.236` |
| `requestEndSkewMs` | `5` | `43.791` | `80.77` | `146.068` |
| `maxRequestDurationMs` | `5` | `37.108` | `103.175` | `144.822` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `5` | `-287.51` | `84.085` | `512.096` |
| `latestClientRegistrationLagMs` | `5` | `-11.149` | `333.618` | `782.47` |
| `maxClientRegistrationAfterServerStartMs` | `5` | `224.923` | `249.533` | `276.361` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
