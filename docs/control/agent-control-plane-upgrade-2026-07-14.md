---
doc_id: agent_control_plane_upgrade_2026_07_14
accountable_role: Tech lead/architect
primary_agent: claude
status: active
created: 2026-07-14
update_triggers:
  - a task in this plan is completed, descoped, or found infeasible
  - the repo control plane changes in a way that invalidates a verified fact
---

# Agent Control Plane Upgrade Plan (2026-07-14)

This plan applies the media-timeline agent-harness cleanup pattern
(`media-timeline/docs/plans/AGENT_HARNESS_IMPROVEMENTS_2026-07-10.md`) to the
HydraCam mobile repo. The unifying theme is the same: **keep the always-loaded
control docs down to invariants and pointers, move journal prose into linked
control docs, and convert prose rules into mechanical enforcement.**

Every "Current state" fact below was verified against the repo on 2026-07-14.
If a fact no longer holds when implementing, stop and re-verify before
proceeding.

## How to use this document

1. Work one task at a time in the listed order unless "Depends on" says
   otherwise.
2. Before each task, re-verify its "Current state" facts. If reality differs,
   update this document in the same change and adapt.
3. After each task, run its acceptance criteria, then the global gate below.
4. Scope discipline: these tasks touch docs, git hygiene, CI, and agent
   tooling. Do NOT modify product code (`lib/`, platform folders) except where
   a task explicitly names a file.
5. Update the task table status when a task starts and finishes.

### Global verification gate

```bash
git diff --check
flutter analyze
```

Run `flutter test` additionally when a task changes anything under `lib/`,
`test/`, or `pubspec.yaml` (none of these tasks should).

## Task overview

| Id | Task | Status | Risk | Depends on |
| --- | --- | --- | --- | --- |
| HCP-1 | Untrack stale `automation_runs/` artifacts | Complete | Low | — |
| HCP-2 | Root noise pruning (stub files, `script/`, `qr.png`) | Complete | Low | — |
| HCP-3 | Markdownlint config + docs quality CI | Complete | Low | — |
| HCP-4 | Change-scoped agent gate script + `.claude/settings.json` | Complete | Low | HCP-3 |
| HCP-5 | Flutter quality CI (analyze + test) | Planned | Medium | — |
| HCP-6 | Slim `AGENTS.md` to invariants + pointers | Planned | Medium | HCP-4 |
| HCP-7 | Refresh `docs/control/README.md` index | Planned | Low | HCP-6 |

---

## HCP-1: Untrack stale `automation_runs/` artifacts

### Goal

`automation_runs/` contains only ignored, local-only run output; git tracks
none of it.

### Current state (verified 2026-07-14)

- `.gitignore` contains `automation_runs/*`.
- 20 files under `automation_runs/` are nevertheless tracked (committed
  2025-11 before the ignore rule): `git ls-files automation_runs | wc -l` → 20.
- The tracked runs are smoke-run JSON from 2025-11-16, superseded by the
  `logs/verification-runs/` evidence-pack convention.

### Steps

1. `git rm -r --cached automation_runs`
2. Confirm the files remain on disk and `git status` shows only deletions of
   the previously tracked paths.

### Acceptance criteria

- `git ls-files automation_runs` returns nothing.
- The files still exist on disk.

---

## HCP-2: Root noise pruning

### Goal

The repo root stops carrying stale pointer stubs and misplaced one-off files
that compete with the control plane during agent orientation.

### Current state (verified 2026-07-14)

- `Current_dev_status.txt` and `GOALS.txt` are ~250-byte compatibility
  pointers to `docs/control/status-and-roadmap.md`, created during the
  2026-06 control-plane migration. The only reference to either is
  `docs/control/history/DEPLOYMENT_GUIDE.md` (itself an archived historical
  doc).
- `qr.png` (14 KB) sits at repo root with zero references in tracked text
  files.
- `script/build_and_run.sh` is the only file in `script/`, while the real
  script home is `scripts/` (85 entries). Zero references to
  `script/build_and_run.sh` outside itself.

### Steps

1. Delete `Current_dev_status.txt` and `GOALS.txt` (`git rm`). Their
   consumers were migrated in 2026-06; `README.md` and `AGENTS.md` already
   point at `docs/control/`. Note the deletion prominently in the commit
   message (recoverable from git history).
2. Annotate the two references in `docs/control/history/DEPLOYMENT_GUIDE.md`
   (one line: files removed 2026-07-14, see `docs/control/`).
3. `git mv script/build_and_run.sh scripts/build_and_run.sh`; remove the now
   empty `script/` directory. Re-grep for `script/build_and_run` afterwards.
4. `git mv qr.png docs/control/history/qr.png` (unreferenced; keep as
   historical artifact rather than deleting a binary the owner may want).

### Acceptance criteria

- Root `ls` no longer shows `Current_dev_status.txt`, `GOALS.txt`, `qr.png`,
  or `script/`.
- `rg 'script/build_and_run|Current_dev_status|GOALS\.txt'` outside
  `docs/control/history/` and this plan returns nothing.

### Implementation record (deviations from verified facts)

- `.codex/environments/environment.toml` also referenced
  `./script/build_and_run.sh` (missed by the original "zero references
  outside itself" fact-check because it's under a dotdir `rg` skips by
  default without `--hidden`). Updated it to `./scripts/build_and_run.sh` in
  the same change since it is a live config, not historical evidence.
- `logs/verification-runs/20260606-2007-evidence-first-loop-tooling/git-status-{before,after}.txt`
  and `logs/verification-runs/20260607-0035-native-macos-controller-run/README.md`
  still contain literal `Current_dev_status.txt`, `GOALS.txt`, and
  `script/build_and_run.sh` strings. These are point-in-time evidence-pack
  transcripts (command output snapshots), not live pointers, and fall under
  the "Explicitly deferred" policy against modifying tracked evidence under
  `logs/`. The acceptance-criteria grep above should be read as excluding
  `logs/verification-runs/` for this reason, matching the deferred-work
  policy at the bottom of this plan.

---

## HCP-3: Markdownlint config + docs quality CI

### Goal

Markdown hygiene and `git diff --check` become CI-enforced on changed files,
so the control docs stay lintable without prose reminders.

### Current state (verified 2026-07-14)

- No `.markdownlint*` config exists.
- `.github/` contains only `copilot-instructions.md`; the repo has NO CI
  workflows at all.
- `AGENTS.md` prose requires `git diff --check` as minimum validation for
  docs-only changes.

### Steps

1. Add `.markdownlint.json` at root mirroring media-timeline's rule set
   (disable MD003, MD007, MD013, MD024, MD028, MD029, MD033, MD036, MD041,
   MD046, MD052, MD056).
2. Add `.github/workflows/docs-quality.yml`:
   - Trigger: `pull_request` and `push` to `master-jose-2025`.
   - Step 1: `git diff --check` over the merge base
     (`git diff --check <base>...HEAD`).
   - Step 2: run `npx --yes markdownlint-cli2` on changed `.md` files only,
     excluding `docs/control/history/` and `logs/`. No changed files → skip.
3. Fix any lint violations this plan's own files introduce. Do NOT mass-fix
   legacy markdown.

### Acceptance criteria

- `npx --yes markdownlint-cli2 AGENTS.md docs/control/README.md docs/control/agent-control-plane-upgrade-2026-07-14.md` passes locally.
- The workflow YAML parses (`ruby -ryaml -e ...` or any YAML parser).

### Implementation record

- `AGENTS.md` had 39 pre-existing markdownlint violations (MD022/MD031/MD032
  blank-line-around-heading/fence/list issues, plus one MD040 missing fenced
  code language) once `.markdownlint.json` existed. Per the parent task's
  instruction that "AGENTS.md and the plan doc must pass," these were fixed:
  `npx --yes markdownlint-cli2 --fix` resolved all but the MD040 case, and the
  `### File Organization` fenced block (a directory tree) was manually tagged
  ` ```text `. Diffed with `--ignore-blank-lines --ignore-all-space` to confirm
  the fix only inserted blank lines and one language tag — no prose changed.
  This is treated as within HCP-3 scope, not a "mass-fix legacy markdown"
  violation, because the acceptance criteria for this task explicitly names
  `AGENTS.md`.
- `docs/control/README.md` and this plan doc had zero violations before the
  config existed.
- No workflow reference implementation was reused verbatim: the
  media-timeline `quality-check.yml` is a multi-service monorepo workflow
  (TypeScript/ESLint/Playwright/self-hosted runner) with no directly portable
  docs-only lane, so `docs-quality.yml` was written fresh for this repo's
  git-diff-check + changed-markdown-only shape, per the plan's own Steps.

---

## HCP-4: Change-scoped agent gate + `.claude/settings.json`

### Goal

The validation rules agents must remember ("run analyze for Dart changes,
`git diff --check` for docs") become one mechanical, change-scoped command,
run automatically at end of turn in Claude Code sessions.

### Current state (verified 2026-07-14)

- No `.claude/settings.json` is checked in (no permission allowlist, no
  hooks).
- Validation policy exists only as prose in `AGENTS.md`.
- `flutter` is on PATH on the dev host (`/opt/homebrew/bin/flutter`).

### Steps

1. Create `scripts/agent_gate.sh`:
   - Compute changed files (staged + unstaged + untracked vs HEAD), or accept
     explicit paths as arguments.
   - Always: `git diff --check`.
   - If any changed `.dart` file: `dart format --set-exit-if-changed
     <changed dart files>` and `flutter analyze --no-pub`.
   - If any changed `.md` file (excluding `docs/control/history/`, `logs/`):
     `npx --yes markdownlint-cli2 <files>`.
   - No changed files → print "clean" and exit 0. Keep it dependency-free
     bash; every network-free step; no output redirected to `/dev/null`.
2. Create `.claude/settings.json`:
   - `permissions.allow` for the commands agents need constantly and that are
     read-only or repo-scoped: `flutter analyze`, `flutter test:*`,
     `dart format:*`, `git status:*`, `git diff:*`, `git log:*`, `rg:*`,
     `bash scripts/agent_gate.sh:*`.
   - `hooks.Stop` → `bash scripts/agent_gate.sh` (change-scoped, so idle
     turns are near-instant). Document in `AGENTS.md` that removing the hook
     entry is the fallback if it proves too chatty.
3. Verify `node -e "JSON.parse(...)"` on the settings file.

### Acceptance criteria

- `bash scripts/agent_gate.sh` passes on a clean tree.
- With a deliberate trailing-whitespace edit in a scratch `.md` file, the
  gate fails; after revert it passes.
- Settings JSON parses.

### Implementation record (deviation from verified facts)

- The dev host's default `/bin/bash` is 3.2 (macOS stock), which has no
  associative arrays. The gate script's de-duplication logic was written with
  `awk '!seen[$0]++'` instead of a bash-4-style `declare -A`, after an initial
  version failed with `declare: -A: invalid option`. Confirmed with
  `bash --version` → `GNU bash, version 3.2.57(1)-release`.
- Verified all three acceptance criteria directly:
  - Clean tree: `bash scripts/agent_gate.sh` printed the change-scoped output
    (no changes other than this task's own new/modified files) and exited 0.
  - Scratch failure: added a trailing-whitespace line to a scratch
    `docs/control/scratch-gate-test.md`, staged it; the gate's `git diff
    --check` and `markdownlint-cli2` (MD009) both flagged it and the script
    exited 1. Reverting (`git reset` + delete) restored an exit-0 pass.
  - `node -e "JSON.parse(...)"` on `.claude/settings.json` printed
    `settings.json OK`.
- Per HCP-4 step 2, documented the Stop-hook removal fallback in `AGENTS.md`'s
  Validation Policy section (new bullet after the "docs-only" line).

---

## HCP-5: Flutter quality CI (analyze + test)

### Goal

`flutter analyze` and `flutter test` run in CI on every PR, so the
AGENTS.md validation policy has a backstop that does not depend on any agent
or harness.

### Current state (verified 2026-07-14)

- No CI exists (see HCP-3).
- Local `flutter analyze` / `flutter test` status must be verified at
  implementation time; if either fails on the current tree, scope CI to the
  passing subset and record the failures here.

### Steps

1. Run `flutter analyze` and `flutter test` locally first. Record results in
   this file. If analyze fails, fix nothing outside docs scope — instead file
   the failures in the task table notes and gate CI on analyze only if it
   passes.
2. Add `.github/workflows/flutter-quality.yml`:
   - Trigger: `pull_request` and `push` to `master-jose-2025`.
   - `subosito/flutter-action@v2` with the stable channel, cache enabled.
   - `flutter pub get`, `flutter analyze --no-pub`, `flutter test --no-pub`.
3. Keep hardware/device/e2e lanes OUT of CI — those remain evidence-pack
   work per `docs/control/evidence-first-loop.md`.

### Acceptance criteria

- Local `flutter analyze` and `flutter test` results recorded below.
- Workflow YAML parses.

### Implementation record

- To be filled at implementation time with the actual local
  `flutter analyze` / `flutter test` results before the workflow is added.

---

## HCP-6: Slim `AGENTS.md` to invariants + pointers

### Goal

`AGENTS.md` drops from 638 lines to ≤ 320 lines with zero information loss:
dated run evidence moves to (or is deduplicated against)
`docs/control/status-and-roadmap.md`, and everything mechanically enforced by
HCP-3/4/5 shrinks to a line + pointer.

### Why

`AGENTS.md` is loaded by every agent session. Its own rules say product
status lives under `docs/control/`, yet lines ~118–328 carry a ~210-line
dated run journal (platform status, run IDs, IP addresses, timing numbers)
duplicating `status-and-roadmap.md`, plus a dated "iOS Physical-Device
Verification" section. That is exactly the drift the control-plane section
prohibits.

### Current state (verified 2026-07-14)

- `AGENTS.md` is 638 lines. The "Current Platform Status" block inside
  "Project Overview" spans ~lines 118–328; "iOS Physical-Device
  Verification" spans ~lines 542–559.
- `docs/control/status-and-roadmap.md` (1,212 lines, refreshed 2026-07-07)
  already contains the platform-status content in near-duplicate form.
- `CLAUDE.md` and `.github/copilot-instructions.md` are already thin
  adapters pointing at `AGENTS.md` — keep them as-is.

### Steps

1. Apply this disposition table ("Move" = cut, merge into target without
   duplication, leave a one-line pointer):

   | AGENTS.md section | Disposition |
   | --- | --- |
   | Agent Control Plane | Keep |
   | Operating Rules | Keep |
   | Worktrees and Branch Hygiene | Keep |
   | Validation Policy | Keep; add one line that `scripts/agent_gate.sh` runs the static subset mechanically and CI backstops analyze/test |
   | Shell and Automation Safety | Keep |
   | Project Overview (first paragraph) | Keep |
   | Current Platform Status (~118–328) | Replace with a ≤ 15-line durable summary (platform support tiers, S7/Xiaomi caveats, where evidence lives) + pointer to `status-and-roadmap.md`. Before deleting each dated fact, verify it exists in `status-and-roadmap.md`; MOVE any missing fact there |
   | Multi-device sync runner usage (the durable `run_rotating_master_slave_matrix.py` flag guidance buried in the status block) | Extract the durable how-to-run guidance (immediate/warm-prime/prime-then-immediate modes, `--expect-target-id`, iOS trust-retry) into `docs/control/regular-evaluation-plan.md` or a short new `docs/control/rotating-matrix-runner.md`, and pointer it |
   | Development Commands | Keep |
   | Architecture | Keep (durable, code-anchored) |
   | Code Style and Conventions | Keep |
   | Session and Media Workflow | Keep |
   | Settings and Configuration | Keep |
   | iOS Physical-Device Verification (~542–559) | Delete; content is dated evidence already superseded by `status-and-roadmap.md`. Keep nothing but the existing pointer in the platform summary |
   | Common Patterns | Keep |
   | Testing Notes | Keep |
   | Dependencies of Note | Keep |
   | Future Development Priorities | Keep (already pointer + durable themes) |
   | NEW: Mechanical Enforcement | Add ~8 lines: gate script, Stop hook, CI workflows, and the rule that mechanically-enforced rules must not be re-expanded into prose |

2. While moving, cut/paste with minimal stitching — do not rewrite facts.
3. Verify zero information loss: for every dated run ID or evidence path
   removed from `AGENTS.md`, `rg <run-id> docs/control/` must hit.

### Acceptance criteria

- `wc -l AGENTS.md` ≤ 320.
- `rg '2026-06-0[6-9]' AGENTS.md` returns no dated journal narrative (a
  durable caveat naming a date is acceptable if ≤ 1 line).
- Every run ID removed from `AGENTS.md` is findable under `docs/control/`
  or was already there.
- `npx --yes markdownlint-cli2 AGENTS.md` passes; gate passes.

---

## HCP-7: Refresh `docs/control/README.md` index

### Goal

The control-plane entrypoint lists every control doc that actually exists,
including this plan, so discovery does not require `ls`.

### Current state (verified 2026-07-14)

- `docs/control/README.md` "Control Documents" omits at least:
  `clock-sync-drift-test-plan.md`, `device-relationship-fsm.md`,
  `time-sync-ground-truth-protocol.md`, `time-sync-two-device-runbook.md`,
  `localization-inventory.md`, `native-android-client-feature-comparison.md`,
  `fixed-camera-hls-implementation-plan.md`, `hybrid-deploy-plan.md`, and
  `hydracam-mobo-media-timeline-merge-plan.md` is listed but this plan is
  not (it did not exist).

### Steps

1. Diff the "Control Documents" list against `ls docs/control/*.md`; add a
   one-line entry for each missing doc (read each doc's opening lines for an
   accurate description — no invented summaries).
2. Add this plan to the list.
3. Do not restructure the rest of the README.

### Acceptance criteria

- Every `docs/control/*.md` file (excluding `history/`) appears exactly once
  in the README index.
- Markdownlint passes on the README.

---

## Explicitly deferred (owner decisions — do not implement)

- **Tracked evidence packs under `logs/`** (5,937 of 6,546 tracked files).
  Current policy intentionally tracks command transcripts and device logs
  (`.gitignore` re-includes them). Moving evidence to LFS/an ignored path
  would change the evidence-first contract — owner decision.
- **Stale remote branch pruning** (`codex/*` 2026-07-07 stack and older
  merged branches): destructive; prepare-only if ever requested.
- **Linear workspace connection** (`backlog-import.md` staging remains the
  queue until then).
- **GEMINI.md adapter**: no Gemini harness is used on this repo today.
