# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `6`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `43.435`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `6` | `310.705` | `717.116` | `1667.801` |
| `set_role` | `6` | `170.105` | `549.024` | `1330.144` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `6` | `0.882` | `1.107` | `1.711` |
| `requestStartSkewMs` | `6` | `111.367` | `430.159` | `1076.972` |
| `requestEndSkewMs` | `6` | `72.346` | `150.156` | `291.066` |
| `maxRequestDurationMs` | `6` | `84.44` | `398.497` | `1038.527` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `6` | `-613.019` | `180.794` | `776.082` |
| `latestClientRegistrationLagMs` | `6` | `-136.038` | `1021.581` | `2498.014` |
| `maxClientRegistrationAfterServerStartMs` | `6` | `357.477` | `840.787` | `1928.104` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `29d816ac550b7ece` | `passed` | `9885e6503930304946`, `RF8M21J8XRT`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
| `9885e6503930304946` | `passed` | `29d816ac550b7ece`, `RF8M21J8XRT`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | s7_exynos_camera_timeout |
| `RF8M21J8XRT` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M90QE7LX`, `00008101-000A68811E43001E`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
| `RF8M90QE7LX` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M21J8XRT`, `00008101-000A68811E43001E`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
| `00008101-000A68811E43001E` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M21J8XRT`, `RF8M90QE7LX`, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
| `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | `passed` | `29d816ac550b7ece`, `9885e6503930304946`, `RF8M21J8XRT`, `RF8M90QE7LX`, `00008101-000A68811E43001E` |  |
