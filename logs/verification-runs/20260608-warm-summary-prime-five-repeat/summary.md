# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `25`
- Repeat role-switch cycles: `5`
- Elapsed seconds: `9.167`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `25` | `19.665` | `201.572` | `370.535` |
| `set_role` | `25` | `48.211` | `162.803` | `361.848` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `25` | `0.295` | `0.429` | `0.686` |
| `requestStartSkewMs` | `25` | `17.396` | `103.348` | `201.923` |
| `requestEndSkewMs` | `25` | `33.752` | `79.56` | `231.263` |
| `maxRequestDurationMs` | `25` | `26.067` | `97.817` | `213.369` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `25` | `-325.415` | `65.82` | `524.32` |
| `latestClientRegistrationLagMs` | `25` | `-109.286` | `321.479` | `974.514` |
| `maxClientRegistrationAfterServerStartMs` | `25` | `179.465` | `255.659` | `510.993` |

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
