# Evidence Run: Scheduled task cancel future cleanup

- Source: docs/control/backlog-import.md#issue-7
- Slug: `scheduled-task-cancel-future-cleanup`
- Verification tier: D (integration-unit-tests)
- Status: prepared

## Acceptance Checks

- [ ] Cancelled scheduled tasks settle the Future returned by scheduleTask
- [ ] Cancellation does not run the callback and removes the task from the scheduler
- [ ] Focused ScheduledTaskService tests, analyzer, diff check, and full Flutter tests pass

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Add screenshots, video, logs, and command notes here.

## Result

- Final disposition: pending
