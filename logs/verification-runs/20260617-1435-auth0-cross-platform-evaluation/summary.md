# Evidence Run: Evaluate Auth0 implementation and cross-project reuse

- Source: user-goal#auth0-cross-project
- Slug: `auth0-cross-platform-evaluation`
- Verification tier: B (emulator-simulator-e2e)
- Status: partial

## Acceptance Checks

- [x] HydraCam Auth0 code path is statically mapped and analyzer/tests identify current breakages
- [x] Every immediately runnable platform is inventoried and either tested or recorded with a concrete blocker
- [x] media-timeline auth gap and reuse path are mapped from current code
- [x] media-timeline now has a provider-switched Auth0 path that can use the KEOB tenant and Google social connection

## Device Matrix

- iPad (5), iOS 17.7.11 21H461, `8b406aa5c597eab4c4dfd9908f4a09b10a89ec63`: visible Flutter iOS target. Unit coverage verifies iOS Auth0 redirect scheme; real interactive Google/Auth0 login was not completed because it requires a user browser credential step.
- macOS 26.4.1 25E253, `macos`: visible Flutter desktop target. HydraCam intentionally rejects interactive Auth0 login on desktop; macOS debug build timed out.
- Chrome 149.0.7827.115, `chrome`: visible Flutter web target. HydraCam intentionally rejects interactive Auth0 login on non-mobile platforms; debug web build passed.
- Android: no attached ADB devices were visible during this run.

## Evidence

- `commands.log`: focused HydraCam auth tests passed, focused analyzer passed, KEOB Auth0 OpenID configuration is reachable, HydraCam web debug build passed, macOS and iOS build lanes timed out.
- media-timeline focused tests passed outside this pack:
  - `cd backend && npx vitest run src/auth/config.test.ts src/auth/routes.test.ts`
  - `cd frontend && npx vitest run src/services/authApi.test.ts`
  - `docker compose -f docker-compose.prod.yml config --quiet`
  - `git diff --check -- backend/src/auth/config.ts backend/src/auth/routes.ts backend/src/auth/session.ts backend/src/auth/config.test.ts backend/src/auth/routes.test.ts frontend/src/services/authApi.ts backend/.env.production.example docker-compose.prod.yml`
- media-timeline backend project typecheck is blocked by an unrelated pre-existing missing `backend/src/services/eventFileInventory.js` import from `backend/src/services/eventFileInventory.test.ts`.

## Result

- Final disposition: partial. The merged Auth0 mechanism is implemented in media-timeline and focused-tested. Full real-login proof still requires configured Auth0 application credentials, callback URL registration, and a human Google login on an attached mobile/browser target.
