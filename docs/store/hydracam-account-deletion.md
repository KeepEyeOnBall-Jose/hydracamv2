# HydraCam Account And Data Deletion Draft

Last updated: 2026-06-09.

This draft is prepared for the public account/data deletion URL required by the
current Auth0 account flow and store submissions. It must be reviewed by the app
owner, connected to the production support process, and published at a public
HTTPS URL before external TestFlight, Google Play testing, or production review.

## Request Deletion

HydraCam users can request deletion of account-linked data by submitting the
email address used for HydraCam sign-in and, when available, the HydraCam GUID
shown in the app. Release builds configured with
`HYDRACAM_ACCOUNT_DELETION_URL` open this page from the Login screen action
named "Request Account Deletion".

## Data Covered

Deletion requests should cover:

- Auth0 account identity data associated with the HydraCam login.
- HydraCam backend user records and identifiers, including HydraCam GUID and
  device/session identifiers when linked to the requesting user.
- Uploaded session metadata, photos, videos, audio, and user-selected gallery
  media associated with the verified account.
- Support diagnostics or local logs that were sent to the support team or
  backend for troubleshooting.

Data stored only on a user's device must be removed from that device by the
user, either through HydraCam's local media/session controls or by uninstalling
the app.

## Verification

Before deleting account-linked data, the production support process must verify
that the requester controls the email address or Auth0 identity connected to
the HydraCam account. If a request includes a HydraCam GUID, use it only as an
additional locator, not as sole proof of identity.

## Timing

The published production page must state the final response timeline and any
legally required exceptions before submission. Until the final process is
approved, treat deletion requests as manual support requests that require owner
review.

## Retention Exceptions

The production service may retain limited records when required for security,
fraud prevention, legal compliance, dispute handling, or backup recovery. The
published policy must list the final retention exceptions and timelines before
submission.

## Contact

Deletion request contact or submission form: to be published before submission.
