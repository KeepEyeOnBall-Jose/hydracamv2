# Cross-repository session handoff index — 2026-10-21

The single entry point for everything that was open across the six
repositories on 2026-10-21. Each one has its own detailed index; this file
says where they are and what is still live.

Every per-repository index lives at the **same path on the same branch name**:

```
docs/archived/2026-10-21-session-handoff-index.md   on   claude/session-handoff-index-20261021
```

To read one without checking anything out:

```bash
git show claude/session-handoff-index-20261021:docs/archived/2026-10-21-session-handoff-index.md
```

| Repository | Local checkout | Index commit | Sessions covered |
|---|---|---|---|
| media-timeline | `/Users/jose/src/work/media-timeline` | `e5d6060f6` (revision 2) | 17 lanes — 13 documented, 4 noted |
| local-explorer | `/Users/jose/src/work/financial-markets/local-explorer` | `8443acfe` | 4 |
| allKEOB | `/Users/jose/src/work/allKEOB` | `fd064a00` | 7 |
| keobbackendcore | `/Users/jose/src/work/backend/keobbackendcore` | `74e912828` | 6 |
| mobo | `/Users/jose/src/work/mobo` | `0bc0de5e` | 1 |
| hydracamv2 | `/Users/jose/src/work/hydracamv2` | `eabec8ff` | 1 — see the warning below |

## Facts that bite, per repository

- **Default branches are not all `main`.** `keobbackendcore` uses
  `Jose-Nov-2025-cleanup`; `mobo` is on `codex/mobo-local-development` locally
  and its remote is named `keobmotherboardweb`, so any `origin/main` reference
  fails there — use `origin/HEAD` or `gh pr list`.
- **media-timeline:** do **not** run `git worktree prune`. Preflight receipts
  live in `$GIT_DIR/worktrees/<name>/preflight-receipt.json` in the *primary*
  checkout, so a blanket prune destroys banked receipts worth 30-40 minutes of
  machine time each. Do not push docs to a lane branch that carries
  `integration:ready` — it voids the receipt baked into the PR body and costs
  the lane its place in the merge train. That is why handoff docs there sit on
  separate `claude/handoff-*` branches.
- **keobbackendcore:** production releases are **on hold since 2026-10-16**
  (`docs/VIEWER_SAFE_RELEASES.md`). `editor_deploy_release.csx` is retired and
  `editor_publish_release.csx --publish` refuses. The Contabo
  `/srv/keob-contabo-jose` image-only `keobweb` swap is safe for saves, but
  **Hetzner staging runs against production SQL — do not save there.**
  Four branches cannot be pushed at all: `feat/port-web-editor` (rejected by a
  pre-receive hook) and three `keob-nodes` branches
  (`claude/tour-image-auto-cleanup-90a9e8`, `claude/autolinker-scope-ca3ff0`,
  `reduce-queue-polling`) for want of write access to `keepeyeonball/keob-nodes`.
- **local-explorer:** PRs 223, 224 and 226 have a deliberate merge order. **224
  is the one to land first** — it is the smallest and it drops a `blob:none`
  checkout filter so `PR Verify` survives runner moves, which is what restores
  honest signal for the other two. PR 208 was closed unmerged at
  2026-10-21T01:36:07Z and superseded by PR 225 which merged **seven seconds
  later**; `scripts/ci/land-agent.mjs` (492 lines) and
  `tests/cli/land-agent.test.ts` (136 lines) never landed. If 208 is revived,
  its ADR must be renumbered: **`0030` is now taken on `main`** by
  `docs/adr/0030-ingest-leo-ledger-revisions-as-dated-snapshots.md`.
  Note `verify:precommit` runs on every commit there and takes about 2.5 minutes.
- **mobo:** PRs 24 and 25 are merged. **26 is the open one** ("Record Live page
  production releases", +60 lines across `docs/live-human-visibility.md` and
  `tools/historical-deliveries/live_page_release.py`, both checks green).

## Work that was rescued from being lost

Two bodies of work existed only on a local disk and are now pushed:

1. **The keobbackendcore iPhone editor branch** — 6 commits, 29 files,
   +1641/-51.
2. **The Win11/WSL CI plan** plus `bootstrap-win11-ci.ps1`.

One branch that looked like unlanded work is not: **allKEOB
`claude/allkeob-cicd-optimization-ac21cf`, commit `47f821c1`** was pushed with
no open PR, which reads as orphaned, but it was squash-merged as **allKEOB
PR #85** on 2026-10-20 (`41b4021da46f8d7ec38fff867447295db8d0457f`, single
parent, so `git merge-base --is-ancestor` says NO and `gh pr list --head` says
MERGED). All 35 files it touches are byte-identical to `origin/main`. Verify
that shape with a content diff, not with ancestry:

```sh
files=$(git diff --name-only $(git merge-base origin/main <branch>)..<branch>)
git diff --stat origin/main..<branch> -- $files   # empty output = fully landed
```

Its content is the resumable `rebalance_dev_18g.py` (receipt
`/var/lib/keob-hetzner/dev-baseline-18g.json` APPLIED; dev at 18432 live and
persistent, staging 4096/4096, five `/opt` scripts patched), the 288-line
`tools/hetzner/dev_memory_window_gc.py` with
`install-dev-memory-window-gc.sh` on a daily timer (first run pruned 122 units
and 61 directories), removal of the dead donors `keob-ci-backend-2` and `-3`,
arm-host `donor_mib` 4096 -> 6144, the `vg_free` guard 300 -> 200 GiB, and a
`KEOB_BACKEND_CHECKOUT` resolver in `test_pipeline_closure_guarantees.py`. The
branch itself can be deleted; nothing is waiting on it.

## hydracamv2 held work that existed nowhere but this disk

`hydracamv2` (`/Users/jose/src/work/hydracamv2`) was found last and was the
only repository of the six with work that had **no backup anywhere**. Its one
session, "Multi-device testing and deployment", had been open since
**2026-09-01** and ran in the primary checkout rather than a worktree, so
nothing distinguishes its changes from later hand-editing.

Three bodies of work were local-only and are **now pushed**, each on its own
branch, with no existing ref moved and nothing reviewed:

| Now on `github` | What it held |
|---|---|
| `claude/session-handoff-index-20261021` (`eabec8ff`) | carries as ancestors the two commits that were ahead of the default branch with no backup: `d33f7044` logout automation for `AutomationBridge` (+81 with its test) and `e5caa4d4` AGENTS.md concision rule |
| `claude/capture-sync-adrs` (`64f73dcc`) | 410 lines — `CONTEXT.md`, three clearance/fleet ADRs, and a **294-line media-timeline autonomous-sync grill handoff** sitting in the wrong repository |
| `claude/camera-feature-gaps-1386cd` (`425229bf`) | 75 lines of native camera-app parity gaps queued for backlog import |

`claude/squash-video-analysis-overview-08c8b7` is local-only as well but holds
no unique commit, so there is nothing in it to lose.

**Still uncommitted and left exactly as found:** 9 modified and 4 untracked
paths on `master-jose-2025` (+147/−102 tracked). The shape of it — an
`auth0_service` change with a matching test, an ephemeral-emulator runner with
a matching test, an emulator-lifecycle doc, a heavily cut automation runbook —
reads as one coherent in-progress piece, not debris, and is worth committing
deliberately. One trap: the untracked
`logs/verification-runs/20261010-1128-apple-design-audit/` is **17 MB of run
output** that almost certainly wants gitignoring, so do not `git add -A` here.

Two gotchas specific to this repository: **the remote is named `github`, not
`origin`**, and the default branch is **`master-jose-2025`**.

## Searching for a handoff doc

`git log --grep='hand.off'` does **not** match the word "handoff". Use:

```bash
git log --all --since=2026-10-20 -i --grep='handoff' --grep='hand off' --grep='hand-off'
```

`find -newermt` is unreliable here, because checking a worktree out refreshes
mtimes across the tree.

## Still live on 2026-10-21, deliberately not archived

**media-timeline, held because the work is mid-flight:**

- PR #2536 triage — hold until it actually merges, verified against `main`'s
  SHA rather than a run's status. Its run was evicted by concurrency twice.
- Ball tracking recovery (#2586) and its two forks — 81% measured correctness
  on a 74-rally holdout, coverage collapse localised to track re-acquisition,
  three follow-ons queued. All three share the worktree
  `exciting-hellman-9ea57c`: take them together or not at all.
- The orchestration session and the two landing sessions it spawned
  (PR #2582 verification, PR #2531 landing).
- Repository improvement priorities (#2561, merged) — its **worktree** now
  holds `claude/merge-train-self-dispatch-actor`, so archiving it would delete
  the merge-train fix's checkout. Archive it only once that branch moves.

**Blocked by live background work, not by anything missing** — each of these
has its handoff written and pushed, so they need nothing but a click in the
sidebar: #2576 runtime_guard, #2574 node_runtime_policy, iPhone editor
improvements, court calibration handoff, CI/CD performance and e2e.

**Still running on their own:** the KEOB tip release and the allKEOB open-PRs
review.
