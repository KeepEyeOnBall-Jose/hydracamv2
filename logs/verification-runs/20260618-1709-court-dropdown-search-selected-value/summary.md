# Evidence Run: Keep court dropdown valid when search filters selected court

- Source: docs/control/backlog-import.md#15-add-consistent-club-and-court-photos-to-venue-selection
- Slug: `court-dropdown-search-selected-value`
- Verification tier: D (integration-unit-tests)
- Status: passed

## Acceptance Checks

- [x] Filtering courts after selecting one does not leave DropdownButton with a value missing from its items
- [x] Court selection callback is not called with an empty GUID when filtered selection is unavailable

## Device Matrix

- Record device model, OS/runtime, serial/UDID, and role here.

## Evidence

- Recorded failing focused widget test before the fix, then reran the focused
  widget test, full widget directory, `flutter analyze --no-pub`,
  `git diff --check`, and full `flutter test --no-pub`.

## Result

- Final disposition: passed
