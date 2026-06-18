# Evidence Run: Reconcile Android toolchain status docs

- Source: docs/control/status-and-roadmap.md#android-toolchain-status
- Slug: `android-toolchain-status-docs`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Status docs reflect current tracked Android Gradle, AGP, Kotlin, and url_launcher_android versions
- [x] No stale wording claims the dependency upgrade is unfinished when tracked files show it landed

## Device Matrix

- Not applicable. This was a docs/control status reconciliation with no app or
  device-facing behavior change.

## Evidence

- `git diff --check` passed.
- Targeted `rg` consistency check captured the tracked source versions:
  Gradle `8.14.5`, Android Gradle Plugin `8.11.1`, Kotlin `2.2.20`, and
  `url_launcher_android: ^6.3.32`.
- `docs/control/status-and-roadmap.md` now describes the Android toolchain bump
  as landed in source and keeps the remaining release concern on signed-AAB and
  store-readiness artifact proof.

## Result

- Final disposition: passed. This run did not rebuild Android artifacts or run
  device smoke tests because the change is docs-only; the updated control docs
  explicitly preserve signed AAB and `scripts/check_store_readiness.sh local`
  as the next artifact-readiness proof.
