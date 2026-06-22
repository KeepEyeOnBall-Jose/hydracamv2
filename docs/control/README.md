# HydraCam Control Plane

This directory is the product/control-plane entrypoint for the HydraCam mobile
repo. It replaces the Google Sheet as the canonical source for durable project
state.

## Source Hierarchy

1. `AGENTS.md` is the canonical agent control plane: repository rules,
   validation policy, worktree hygiene, and durable agent operating agreements.
2. `docs/control/README.md` is the product/control-plane entrypoint: current
   status, roadmap, requirements, imported backlog, architecture, and test
   strategy.
3. Linear is the preferred home for actionable work once the Linear workspace,
   team, and project are connected. Until then, `backlog-import.md` is the
   deterministic import queue.
4. Historical docs and runbooks remain useful evidence, but should point back to
   this directory when they overlap with current status or roadmap.

## Deprecated Google Sheet

Historical source snapshot:

- Title: `HydraCam Dev Process`
- URL: <https://docs.google.com/spreadsheets/d/1oIx87GGDubiFSvvE38Hm79293y6sLLlPrtSJ6PPM6J4/edit>
- Read date: 2026-06-05
- Locale/time zone: `es_ES`, `Europe/Paris`
- Disposition: deprecated as canonical control tool; retained as historical
  source provenance only.

The sheet is not an app runtime input. Do not add new project status, sprint
planning, requirements, or backlog rows there unless explicitly preserving
history.

## Migration Reconciliation

The 2026-06-05 sheet import produced these source counts:

| Source tab | Disposition | Count |
| --- | --- | ---: |
| `FALLOS Y MEJORAS` / `(EN)` open rows | Linear candidates, de-duplicated bilingual source | 25 |
| `FALLOS Y MEJORAS` / `(EN)` completed rows | Historical archive only | 21 |
| `JAVI IMMEDIATE BACKLOG` open rows | Linear candidates, grouped by mobile theme | 24 |
| `JAVI IMMEDIATE BACKLOG` completed rows | Historical archive only | 94 |
| `Functional Requirements` open rows | Requirements retained; mobile rows staged for issues, backend rows marked external | 26 |
| `Non Functional Requirements` open rows | Quality gates retained in Markdown | 16 |
| `Testing table` open rows | Test strategy retained; high-value gaps staged for issues | 23 |

The `Index` and `Rules` tabs are replaced by this file. `Sprint Plan` and
`SPRINT PLAN FUTURO PARA FUNCIONAMIENTO DESATENDIDO` are planning history;
still-relevant open tasks are represented in `backlog-import.md` rather than as
spreadsheet sprint rows.

## Control Documents

- `status-and-roadmap.md`: current mobile status, release blockers, roadmap, and
  future product ideas separated from active mobile work.
- `baseline-functionality-and-support.md`: basic support contract for baseline
  functionality, supported hardware, emulator/simulator scope, and minimum
  gates before making support claims.
- `requirements.md`: FR/NFR inventory preserving source IDs, dependencies,
  completion state, and mobile/backend scope.
- `backlog-import.md`: Linear-ready issue candidates with source rows, labels,
  priority, and acceptance checks.
- `architecture-and-testing.md`: attended/unattended architecture notes,
  Auth0 components, diagrams source, and test matrix.
- `hydracam-visual-makeover-plan.md`: squash design-system alignment plan for
  making the mobile app visually homogeneous with media-timeline.
- `user-flow-tracker.md`: derived user-flow map tying product journeys to
  current evidence packs, validation gates, and open proof gaps.
- `user-flow-fsm-diagrams.md`: Mermaid FSM diagrams for HydraCam app journeys
  and the related MoBo service/media-timeline lifecycle states.
- `evidence-first-loop.md`: recurring advancement loop and required evidence
  pack contract for hardware/emulator-backed verification.
- `regular-evaluation-plan.md`: recurring app-change evaluation gates and quick
  lanes for static checks, emulator/simulator UI, hardware capture, multi-device
  role switching, and release readiness.
- `local-ide-emulator-deploy-playbook.md`: local IDE setup and manual steps for
  VS Code, Android Studio, Xcode, emulator runs, device runs, and release/deploy
  lanes.
- `wireless-device-debugging.md`: Android ADB-over-WiFi and iPhone
  Xcode/CoreDevice setup for cable-free real-device debugging.
- `fleet-operations-plan.md`: lab-managed always-on Android fleet plan,
  heartbeat contract, remote-operations boundaries, and S10e soak harness.
- `macos-dev-host.md`: one-command deployment and validation for a new Mac
  development host over SSH/Tailscale.
- `win11-dev-host.md`: current Win11 host identity, installed toolchains,
  Windows/Android/WSL validation results, USB camera inventory, and remaining
  host-readiness gaps.
- `win11-triple-platform-proof-wrapup-2026-06-09.md`: aborted Win11
  Windows/Linux/Android emulator capture/upload and role-matrix proof attempt;
  records the partial evidence and the remaining blockers.
- `store-privacy-and-metadata.md`: store privacy/data-safety, support URL,
  review-note, and beta-readiness checklist for App Store Connect and Google
  Play.
- `android-auth-sign-in-decision.md`: Android human-login decision record for
  keeping Auth0 Universal Login in the current release lane and deferring native
  Credential Manager until backend/Auth0 account linking is specified.
- `../../scripts/check_store_readiness.sh`: local/upload preflight for store
  IDs, permission metadata, launch assets, artifact presence, and submission
  credentials/URLs.
- `../store/hydracam-privacy-policy.md`, `../store/hydracam-support.md`, and
  `../store/hydracam-account-deletion.md`: publish-ready drafts for required
  store URLs; review and host publicly before external beta or production
  review.
- `hydracam-mobo-media-timeline-merge-plan.md`: cross-repo convergence plan for
  the HydraCam mobile app, MoBo HydraCam webservice, and media-timeline event
  and media backend.
- `cross-project-api-data-map.md`: Mermaid diagrams for current and target API
  calls, endpoint families, storage ownership, and cutover boundaries across
  HydraCam mobile, MoBo, and media-timeline.
- `wearable-replay-integration-plan.md`: player-worn Ray-Ban Meta and Galaxy
  Watch4 replay lane, local wearable sidecars, sync proof, feedback boundaries,
  and media-timeline replay targets.
- `../superpowers/plans/2026-06-07-win11-dev-host-storage-cleanup.md`: executable
  Win11 C: cleanup and dev-environment moveout plan backed by SSH disk
  inventory.

## Historical Status Files

These files are retained as dated evidence only. They now carry historical
warnings and must not override `status-and-roadmap.md`:

- `RECOVERY_PLAN.md`
- `TESTING_SUMMARY.md`
- `READY_TO_DEPLOY.md`
- `BUILD_COMPLETE.md`
- `SUCCESS_SUMMARY.md`
- `DEPLOYMENT_STATUS.md`
- `DEPLOYMENT_GUIDE.md`
- `QUICKSTART.md`
- `MIGRATION_NOTES.md`
- `FINAL_STATUS.md`

## Update Rules

- Update Markdown first for durable repo state.
- Create or update Linear issues for actionable tasks after the Linear
  connector is available.
- Mark backend/web/Azure-only work as `external-backend` unless it directly
  affects this mobile app.
- Preserve source IDs (`F*`, `FR-*`, `NFR-*`, `T-*`) in issue bodies and docs so
  future imports remain auditable.
- Use `docs/control/evidence-first-loop.md` for recurring advancement work.
  Device-facing changes need `logs/verification-runs/...` evidence with
  screenshots, video, and device logs tied to the selected existing item.
- For docs-only changes, `git diff --check` is the minimum validation.
