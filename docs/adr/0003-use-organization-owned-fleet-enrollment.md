# Use organization-owned fleet enrollment

Each Managed Fleet Phone is enrolled into an organization or venue with its own
revocable device credential, while Fleet Operators receive role-based authority
to issue audited commands. A locally generated device UUID, a shared venue
secret, and the Auth0 identity of whoever last used the phone are not sufficient
device authority; this adds enrollment and credential-rotation operations in
exchange for isolating compromise and making phone replacement, venue transfer,
and command attribution explicit.
