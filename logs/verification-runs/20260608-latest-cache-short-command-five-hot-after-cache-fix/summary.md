# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `25`
- Repeat role-switch cycles: `5`
- Elapsed seconds: `7.598`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `25` | `96.121` | `162.755` | `212.408` |
| `set_role` | `25` | `46.141` | `138.639` | `273.157` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `25` | `0.358` | `0.54` | `0.91` |
| `requestStartSkewMs` | `25` | `16.304` | `95.58` | `157.341` |
| `requestEndSkewMs` | `25` | `34.428` | `62.643` | `139.083` |
| `maxRequestDurationMs` | `25` | `23.713` | `79.831` | `135.0` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `25` | `-341.675` | `59.536` | `529.683` |
| `latestClientRegistrationLagMs` | `25` | `-129.194` | `261.61` | `714.099` |
| `maxClientRegistrationAfterServerStartMs` | `25` | `135.457` | `202.074` | `324.108` |

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
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `macos` | s7_exynos_camera_timeout |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `00008101-000A68811E43001E`, `macos` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `macos` |  |
| `macos` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
