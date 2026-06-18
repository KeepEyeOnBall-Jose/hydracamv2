# Evidence Run: Settings async update lifecycle

- Source: docs/control/backlog-import.md
- Slug: `settings-update-dispose-mounted-guards`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Settings update handlers must not call setState after the settings screen is disposed while an async write is pending.

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
