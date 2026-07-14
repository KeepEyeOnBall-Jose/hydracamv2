# Rotating Master/Slave Matrix Runner

How-to guidance for `scripts/run_rotating_master_slave_matrix.py`, the
multi-device role-switch runner. This doc captures durable flag semantics and
operational caveats extracted from `AGENTS.md` during the 2026-07-14
control-plane slim-down (`docs/control/agent-control-plane-upgrade-2026-07-14.md`,
HCP-6). For command examples, start with
`docs/control/regular-evaluation-plan.md` ("Multi-Device Lanes"). For dated
run evidence, timings, and device inventories, see
`docs/control/status-and-roadmap.md`.

## Modes

- `--immediate-role-switch`: the fastest normal repeat loop. If the latest
  warm-summary cache exists, it uses the full cached target set automatically
  and skips Flutter/ADB discovery plus master-host probing. It stages the
  promoted master first, then dispatches all slave role changes in parallel,
  because current evidence shows that is faster end-to-end than sending all
  devices at once. This is intentionally a no-launch fast path — use it only
  after `/healthz` proves every selected bridge is currently warm.
- `--warm-prime-only`: use first when selected bridges are cold. It reuses
  running bridges, skips build/install, attempts only the missing standby
  launches, writes `warm-bridge-prime.json`, and does not run rotations.
- `--prime-then-immediate-role-switch`: the preferred combined command. It
  primes any missing bridges and then runs the immediate role-switch proof
  only once every selected bridge is warm. If the iPhone Profile bridge may be
  cold, pair it with `--fast-ios-launch` as the one-command path.
- `--fully-parallel-role-switch`: diagnostic comparison only, not the default.
  Current evidence favors the default staged-master-then-parallel-slaves path
  over sending every device's role change at once.

## Target selection and the latest-cache

- Successful warm role-switch runs update
  `logs/verification-runs/latest-rotating-master-slave-warm-summary.json`.
  Only parsed CLI runs with a configured latest-cache path update that durable
  cache; manually constructed test namespaces skip cache writes so unit tests
  cannot poison the hot-run target set.
- Add repeated `--expect-target-id` flags for every device intended to be in
  the run before claiming an all-device or complete selected-set result. That
  writes `expected-targets.json` and fails before build/install/launch when a
  warm summary or filter omits an expected device, and this mode also fails
  before build/install/standby-launch if any selected automation bridge is
  missing or stale.
- Use selected `--target-id` filters only when intentionally narrowing the
  run.
- To pin a specific prior run instead of the latest cache, pass
  `--warm-summary logs/verification-runs/<last-good-run>/summary.json`.

## Physical iOS bridge hosts

- Cached immediate reruns skip the default physical-iOS LAN host scan unless
  `--auto-ios-bridge-hosts` is passed explicitly; stale cached iOS hosts are
  caught by the identity-matched warm-bridge preflight. Keep the identity-based
  auto host scan enabled for immediate loops, and do not hard-code a prior
  stale host.
- For a selected iPhone+iPad pair, prefer `--no-auto-ios-bridge-hosts` with
  explicit `--ios-host <target-id>=<ip>` flags when explicit LAN hosts are
  supplied; otherwise identity auto-scan can adopt the iPhone link-local
  bridge and poison expected remote-client IP checks.

## Physical iOS Profile build/install

- Physical iPhone no-tooling fast launch requires a Profile automation build.
  A debug `Runner.app` launched with `devicectl` exits before Dart starts,
  with "Cannot create a FlutterEngine instance in debug mode without Flutter
  tooling or Xcode."
- Use the runner's `--ios-profile-build-install` path. On older physical iOS
  devices where `devicectl install` cannot see the device, the runner falls
  back to IPA packaging plus `flutter install --use-application-binary`.

## iOS developer-profile trust retry

- If `xctrace` reports `ios_profile_not_trusted`, the remaining step is on the
  device: Settings > General > VPN & Device Management, trust the developer
  profile, keep the device unlocked, then rerun the warm-prime/immediate
  command.
- To avoid restarting the command while doing that device-side step, add
  `--ios-profile-trust-retry-timeout <seconds>` to a warm-prime or
  prime-then-immediate run. The runner retries the missing physical iOS
  bridge and records `iosProfileTrustRetryAttempts` in `warm-bridge-prime.json`.

## Role-switch artifact fields

- Failed warm-prime artifacts include `deviceActions` with the concrete
  operator step for each still-missing bridge.
- Role-switch artifacts include `requestStartSkewMs` in each
  `runtime-role-switch.json`, per-rotation `phase-timings.json`, and
  connected-client `registeredAt` / `masterServerStartedAt` timestamps, so
  parallel dispatch, master-command readiness, and connected-client
  verification are measured directly rather than inferred from elapsed time.
  Current timing evidence shows dispatch is already sub-millisecond; the
  remaining latency is promoted-master server startup plus client
  registration after server start, which is why staging the master before the
  slave batch beats fully parallel role switching.

## macOS standby caveats

- `HYDRACAM_AUTOMATION_PORT` is a compile-time Dart define. The direct
  detached debug-app launcher normally listens on the compiled default port
  `4762`, and the runner normalizes cold direct-macOS targets to that port
  unless an already-running identity-matched bridge is adopted.
- Prefer the direct detached debug-app launcher for macOS standby;
  Flutter-launched macOS standby processes have not been reliable warm
  bridges across runner exits.

## Runtime safety

Runtime role switching should keep zero-duration automation routes and
identity-safe client/socket cleanup; otherwise rapid back-to-back rotations
can leave stale slave screens or stale sockets that dispose or hide the newly
promoted master.
