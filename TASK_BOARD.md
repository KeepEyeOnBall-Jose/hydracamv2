# Task board

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
