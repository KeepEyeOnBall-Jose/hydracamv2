# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `5`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `1.659`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `5` | `155.324` | `196.016` | `297.077` |
| `set_role` | `5` | `48.879` | `128.896` | `198.648` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `5` | `0.455` | `0.538` | `0.807` |
| `requestStartSkewMs` | `5` | `18.202` | `94.013` | `156.392` |
| `requestEndSkewMs` | `5` | `39.78` | `54.66` | `67.833` |
| `maxRequestDurationMs` | `5` | `30.518` | `78.373` | `130.618` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `5` | `-346.91` | `60.646` | `445.678` |
| `latestClientRegistrationLagMs` | `5` | `-143.808` | `298.713` | `771.223` |
| `maxClientRegistrationAfterServerStartMs` | `5` | `194.281` | `238.067` | `325.545` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
