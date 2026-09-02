# Require end-to-end proof before automatic clearance

HydraCam defaults to automatically clearing a Captured Original, but only after
the device durably retains a Clearance Receipt binding the original's SHA-256
and byte length to its File Registry identity, event linkage, and backend
acceptance. Transport completion, an HTTP success response, or registration
without event linkage never authorizes clearance; this deliberately accepts
longer local retention and possible storage pressure to prevent irreversible
loss of media that cannot be proven complete and attributable end to end.
No Fleet Operator or remote command may bypass the phone's comparison of that
receipt with the exact local bytes it would remove; a device-management wipe is
a separate administrative operation, not media clearance.
