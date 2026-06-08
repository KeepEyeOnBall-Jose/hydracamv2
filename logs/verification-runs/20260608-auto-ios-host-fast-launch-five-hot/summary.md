# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `10`
- Repeat role-switch cycles: `2`
- Elapsed seconds: `9.302`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `10` | `115.482` | `726.987` | `5073.438` |
| `set_role` | `10` | `90.599` | `199.128` | `313.712` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `10` | `0.377` | `0.466` | `0.678` |
| `requestStartSkewMs` | `10` | `22.597` | `131.402` | `230.937` |
| `requestEndSkewMs` | `10` | `42.616` | `84.924` | `140.838` |
| `maxRequestDurationMs` | `10` | `43.799` | `128.921` | `216.279` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `10` | `-329.417` | `92.343` | `489.597` |
| `latestClientRegistrationLagMs` | `10` | `25.932` | `874.622` | `5146.383` |
| `maxClientRegistrationAfterServerStartMs` | `10` | `192.874` | `782.279` | `5131.536` |

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
