# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `10`
- Repeat role-switch cycles: `2`
- Elapsed seconds: `3.781`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `10` | `87.201` | `206.732` | `393.429` |
| `set_role` | `10` | `57.463` | `168.282` | `325.379` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `10` | `0.382` | `0.591` | `1.648` |
| `requestStartSkewMs` | `10` | `25.195` | `103.189` | `180.051` |
| `requestEndSkewMs` | `10` | `32.58` | `80.675` | `164.736` |
| `maxRequestDurationMs` | `10` | `30.76` | `90.336` | `160.44` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `10` | `-329.307` | `67.086` | `482.897` |
| `latestClientRegistrationLagMs` | `10` | `-92.34` | `329.308` | `784.767` |
| `maxClientRegistrationAfterServerStartMs` | `10` | `187.305` | `262.222` | `355.215` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
