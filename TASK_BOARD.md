# Task board

## PR25 manual exposure review — 2026-10-25

- Owner: sequential review; isolated `codex/review-pr25-fix-20261025`;
  current default `f101b766` integrated. Original published head `a3855972` is
  preserved as an ancestor; final normal PR qualification is pending.
- Repairs retain the original exposure owner/control and recording future,
  report pending/error relock truth, coalesce bounded cleanup, reject stale
  camera/session results, and preserve immutable per-path recovery metadata.
  Failed starts schedule hardware cleanup without relying on a visible STOP.
- Actual source evidence: initial seven Dart regressions failed first; vendor
  lifecycle 10, snapshot 6 and consumer 7 cases passed in run `40237419446`.
  Native identity baseline `40239147623` executed 10 cases: 3 passed, 7
  assertions failed, zero skipped/errors. Identity repair and nearby ownership
  16-case validation await the combined native GREEN run.
- Latest diagnostic full suite `40239133047`: 802 passed, one failed, one
  existing gated live-upload skip. The remaining recovery fixture returned a
  nested nullable Future before its ACK; an exact pinned-Dart probe reproduced
  that issue and explicit awaits corrected it. New failed-start observer tests
  and final combined source still require current-head normal CI.
- CameraX 1.6.2 retains camera-scoped request options through graph replacement;
  no normal-path exposure-reset counterexample established. First-frame and
  whole-clip acceptance remain unverified. Historical 16-preset phone receipts
  do not qualify the repaired head or prove court streak quality.
- Device data/apps and shared services preserved; no review capture/install or
  release performed yet. Next: final normal/native results, an admitted current
  APK/build route, then an idle-owner physical smoke with uploads off. Raw logs,
  exact source hashes, commands and process settlement remain under
  `logs/backlog-dispatch-20261025/pr25/`; diagnostic workflow branches are
  excluded from product source.

## PR17 review completion — 2026-10-22

- Owner: sequential review; isolated `codex/pr17-reviewed`; current main
  `bf6ce477` integrated. User selected17 as the final PR, then stop.
- Fixed cancelled-login loss of pending/in-flight rotated credentials; logout
  and replacement-account fencing retained. Four regressions failed first.
- Focused48 tests/zero skips, targeted analysis/format and independent reviews
  pass. Full743 tests/one existing gated skip and full analysis pass. Android
  compilation and final CI pending.
- Source integration only; live-account/device and delegated API release gates
  remain. PR24 stays unmerged; primary checkout and device data untouched.
- [Migration and review evidence](docs/control/human-session-continuity.md).

## Original human session continuity work — 2026-10-09

- Owner: client-auth chat 01a1207f; baseline `6e83866bd`.
- Implemented: refresh serialization, transient retention, logout/GUID fencing,
  atomic secure-store envelope, retained-capture human owner gate.
- Validation: 726 tests pass, one opt-in live wearable-upload proof skipped;
  format/analyzer pass. Android bundle fails: SDK/JDK absent on remote host.
- Status: draft implementation; unit doubles are not live acceptance.
- Blockers: real devices, Android SDK for APK, delegated human API contract.
- [Migration, rollback and acceptance](docs/control/human-session-continuity.md).
