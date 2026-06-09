# Rotating Master/Slave Matrix

- Status: `passed`
- Shared barrier per rotation: `True`
- Rotation count: `2`
- Repeat role-switch cycles: `1`
- Elapsed seconds: `0.45`

| Phase | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `connected_clients` | `2` | `67.868` | `144.889` | `221.911` |
| `set_role` | `2` | `76.034` | `77.575` | `79.116` |

| Runtime Switch Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `parallelRequestStartSkewMs` | `2` | `0.0` | `0.0` | `0.0` |
| `requestStartSkewMs` | `2` | `48.142` | `51.854` | `55.566` |
| `requestEndSkewMs` | `2` | `43.779` | `47.01` | `50.241` |
| `maxRequestDurationMs` | `2` | `30.786` | `31.457` | `32.129` |

| Client Registration Metric | Count | Min ms | Avg ms | Max ms |
| --- | ---: | ---: | ---: | ---: |
| `masterServerStartLagMs` | `2` | `188.37` | `217.454` | `246.539` |
| `latestClientRegistrationLagMs` | `2` | `358.27` | `381.23` | `404.189` |
| `maxClientRegistrationAfterServerStartMs` | `2` | `111.731` | `163.775` | `215.819` |

| Master | Status | Clients | Notes |
| --- | --- | --- | --- |
| `00008101-000A68811E43001E` | `passed` | `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` |  |
| `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63` | `passed` | `00008101-000A68811E43001E` |  |
