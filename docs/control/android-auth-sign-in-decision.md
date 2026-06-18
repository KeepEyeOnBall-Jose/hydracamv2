# Android Auth Sign-In Decision

Date: 2026-06-17

## Decision

Keep HydraCam on Auth0 Universal Login through the existing `AuthService`
abstraction for the current release lane. Do not add Android Credential Manager
or Sign in with Google as a parallel production sign-in path until the Auth0
tenant and HydraCam backend have an explicit account-linking contract for the
returned Google identity.

This means the near-term Android behavior remains a browser or Chrome Custom
Tab backed OAuth flow, with app-side secure credential persistence, restore,
refresh, logout, and HydraCam GUID lookup handled in the current service layer.

## Options Compared

| Option | Fit | Cost | Decision |
| --- | --- | --- | --- |
| Current `flutter_appauth` + project credential store | Already wired in `pubspec.yaml`, `AuthService`, `UserService`, Android redirect manifest, and focused tests. The package is a Flutter bridge over AppAuth for OAuth 2.0 and OpenID Connect providers. | Still depends on browser/Custom Tab UX and app-owned credential management. | Keep for release lane. |
| Migrate to `auth0_flutter` | Auth0-owned Flutter SDK includes Web Authentication, default scopes including `offline_access`, automatic credential deletion on logout for Web Auth, ID-token validation, and Credentials Manager examples. | Migration would touch login, restore, refresh, logout, platform redirects, and mobile smoke evidence. It does not by itself create Android's native account-picker UI. | Defer until there is a reason to replace the current tested auth service. |
| Android Credential Manager / Sign in with Google | Android's recommended Credential Manager API provides a unified bottom sheet for passkeys, passwords, federated sign-in, and Sign in with Google. | Adds an Android-specific identity path, Google Cloud/brand prerequisites, Auth0 user-linking decisions, backend GUID mapping, privacy review, and real-device account-switch proof. | Do not implement for this release without a backend/Auth0 linking spec. |

## Implementation Boundary

- Keep `AuthService` as the app's only human-auth interface.
- Keep refresh-capable scopes and secure credential storage in the current
  service layer.
- Keep logout clearing local credentials even when platform browser logout is
  unavailable.
- Keep desktop/macOS unsupported for interactive human login unless a separate
  desktop auth decision is made.

## Release Gates

- Android and iOS login smoke on real devices or release-representative
  simulators.
- Android process-death restore after browser authentication.
- Android account-switch and logout proof that the previous user's credentials
  are not silently reused.
- Privacy/data-safety review remains unchanged while no additional native
  Google identity data is collected.

## Sources

- `pubspec.yaml` currently pins `flutter_appauth` and
  `flutter_secure_storage`.
- `lib/services/auth0_service.dart` owns login, restore, refresh, logout, and
  credential storage behind test seams.
- `docs/control/backlog-import.md` issue 12 tracks the Android-native
  account-picker question.
- Auth0 Flutter SDK examples:
  <https://github.com/auth0/auth0-flutter/blob/main/auth0_flutter/EXAMPLES.md>
- Flutter AppAuth package:
  <https://pub.dev/packages/flutter_appauth>
- Android Credential Manager overview:
  <https://developer.android.com/identity/credential-manager>
- Android Sign in with Google via Credential Manager:
  <https://developer.android.com/identity/sign-in/credential-manager-siwg>
