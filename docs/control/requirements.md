# HydraCam Requirements

Source: deprecated Google Sheet `HydraCam Dev Process`, read 2026-06-05.

Scope labels:

- `mobile`: actionable in this Flutter repo.
- `external-backend`: owned by backend/web/Azure work unless mobile integration
  is explicitly requested.
- `cross-project`: requires coordinated mobile plus backend/web work.
- `historical-done`: imported as completed source context only.

## Open Functional Requirements

| Source row | ID | Requirement | Priority | Dependencies | Scope | Disposition |
| ---: | --- | --- | --- | --- | --- | --- |
| 6 | FR-004 | Create Azure SignalR Service | High | FR-003 | external-backend | Track outside this repo; mobile may consume later. |
| 9 | FR-007 | Create Azure Queue Service | Medium | FR-003 | external-backend | Track outside this repo. |
| 26 | FR-024 | Create Material Retrieval Endpoint | Medium | FR-016 | external-backend | Mobile dependency for viewing/retrieving session materials. |
| 30 | FR-028 | Create Azure Queues | High | FR-007 | external-backend | Duplicates FR-007 theme; consolidate in backend tracker. |
| 31 | FR-029 | Define Message Formats | High | FR-028 | cross-project | Mobile needs contracts once backend exists. |
| 32 | FR-030 | Model Delivery Package | High | FR-028 | external-backend | Track outside mobile unless app UI consumes package states. |
| 33 | FR-031 | Notify on Completion | Medium | FR-030 | cross-project | Mobile notification handling is a later integration task. |
| 34 | FR-032 | Process Messages | High | FR-028 | external-backend | Track outside this repo. |
| 35 | FR-033 | Update Materials | Medium | FR-032 | external-backend | Mobile may need refresh behavior later. |
| 49 | FR-045 | API: Preview Stream | Medium | FR-043 | cross-project | Mobile camera preview producer/consumer needs a design before implementation. |
| 50 | FR-046 | Mobile App: Show Camera Previews | Medium | None | mobile | Stage as Linear candidate. |
| 51 | FR-047 | Synchronize Time via NTP | Medium | None | mobile | Stage as Linear candidate; impacts capture synchronization. |
| 52 | FR-048 | Estimate Upload Time | Low | FR-040 | mobile | Stage as Linear candidate under upload progress. |
| 53 | FR-049 | Configure SignalR Hub | High | FR-004 | external-backend | Track outside this repo. |
| 54 | FR-050 | Device Connection to SignalR Hub | High | FR-049 | cross-project | Mobile integration depends on backend hub availability. |
| 55 | FR-051 | Notify Devices to Start Session | High | FR-050 | cross-project | Mobile must support receive/act once backend contract exists. |
| 56 | FR-052 | Live Monitoring of SignalR Messages | Medium | FR-049, FR-051 | external-backend | Track outside this repo unless a mobile debug view is requested. |
| 57 | FR-053 | User Session Initialization View | Medium | FR-010 | external-backend | Web/frontend dependency for unattended flow. |
| 58 | FR-054 | API: Start Session Request | High | FR-053 | external-backend | Backend dependency for unattended flow. |
| 59 | FR-055 | Generate QR Code for Session | Medium | FR-054 | external-backend | Track outside mobile unless QR scanning is scoped here. |
| 60 | FR-056 | Notify QR Session Confirmation | Medium | FR-055 | cross-project | Mobile behavior depends on backend contract. |
| 63 | FR-058 | Host GDPR Document in the Application | High | FR-057 | cross-project | Decide whether mobile hosts, links, or consumes web-hosted document. |
| 64 | FR-059 | Integrate GDPR Consent Before Recording | High | FR-058, FR-035 | cross-project | Mobile recording gate if product requires consent in app. |
| 65 | FR-060 | API: Create Session with Primary User | High | FR-019, FR-010 | external-backend | Backend dependency for player/user assignment. |
| 66 | FR-061 | API: Manage Users in Session | High | FR-060 | external-backend | Backend dependency for player/user assignment. |
| 67 | FR-062 | Flutter App: Assign Users to Session | Medium | FR-061 | mobile | Stage after backend API contract exists. |

## Non-Functional Requirements

All NFR rows were open in the sheet. Keep these as quality gates; create Linear
work only where the gate maps to a concrete mobile task.

| Source row | ID | Theme | Requirement | Priority | Scope | Gate |
| ---: | --- | --- | --- | --- | --- | --- |
| 3 | NFR-001 | Security | HTTPS for all communications | High | cross-project | Mobile API endpoints must use HTTPS outside local network flows. |
| 4 | NFR-002 | Security | Secure database connections | High | external-backend | Backend-owned; mobile should not hold DB credentials. |
| 5 | NFR-003 | Security | Authentication token storage | High | mobile | If human login persists beyond the current process, use secure credential storage plus refresh/expiry handling; do not store Auth0 access or refresh tokens in plain shared preferences. |
| 6 | NFR-004 | Performance | API response time under 1 second for 95% typical load | Medium | external-backend | Mobile should expose useful pending/error states for slow responses. |
| 7 | NFR-005 | Performance | Real-time communication latency under 1 second | Medium | cross-project | Validate master/slave or SignalR control latency with tests. |
| 8 | NFR-006 | Scalability | Azure Web App supports 10,000 concurrent users | High | external-backend | Backend-owned. |
| 9 | NFR-007 | Scalability | SignalR supports 5,000 concurrent connections | High | external-backend | Backend-owned. |
| 10 | NFR-008 | Scalability | Azure Queues handle 1,000 messages per second | Medium | external-backend | Backend-owned. |
| 11 | NFR-009 | Maintainability | CI/CD pipeline | High | mobile | Add mobile analyze/test/build automation when repo is stable enough. |
| 12 | NFR-010 | Maintainability | Logging and monitoring | High | mobile | Keep app logging through `LogService`; define mobile diagnostics expectations. |
| 13 | NFR-011 | Maintainability | Documentation | Medium | mobile | Keep `docs/control` current and link stale docs back here. |
| 14 | NFR-012 | Reliability | Database backup | High | external-backend | Backend-owned. |
| 15 | NFR-013 | Reliability | Retry logic for queue processing | Medium | external-backend | Mobile uploader retry logic is separate and should be tested in this repo. |
| 16 | NFR-014 | Usability | User-friendly error messages | Medium | mobile | Apply to session creation, upload, permissions, network, storage, and battery paths. |
| 17 | NFR-015 | Usability | Cross-browser compatibility | Medium | external-backend | Web-owned unless Flutter web support is active. |
| 18 | NFR-016 | Usability | Localization to English, Spanish, and German | Low | mobile | Track as a future localization task if product needs it. |

### NFR Evidence Notes

- 2026-06-18 NFR-010 logging trace retry note:
  `logs/verification-runs/20260618-1330-log-service-trace-retry/` proves
  `LogService` no longer permanently disables trace persistence after a
  transient documents-directory/path failure, waits for queued trace writes
  before reading persisted lines, and suppresses repeated debug noise while
  retrying later log writes. Focused `LogService` coverage, full
  `flutter test --no-pub`, and `flutter analyze --no-pub` passed.

## Completed Functional Requirements

The sheet marked 39 functional requirements complete. Treat those rows as
historical evidence, not proof of current implementation. Re-verify in code,
tests, backend, or devices before relying on a completed state for release.

Important completed mobile-facing themes included:

- Auth0 setup and mobile authentication integration. Current repo evidence shows
  this is only a baseline browser-backed login flow, not completed login restore,
  secure persistent credentials, logout/end-session handling, Android
  process-death recovery, or Android-native account-picker UX.
- Flutter app creation, store upload prep, recording session start/end, local
  recording, upload recording, and readiness notification.
- Basic raw-material view and GDPR compliance document creation.

Completed states from the sheet should not override current repo facts.
