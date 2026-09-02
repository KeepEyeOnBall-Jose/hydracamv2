# HydraCam Capture and Sync

The shared language for capturing media on HydraCam devices and making those
materials durably available to Media Timeline.

## Language

**Captured Original**:
The exact photo or video file produced or adopted by a HydraCam device before
any transfer, processing, or derivation.
_Avoid_: source file, local copy, raw material

**Sync Item**:
One Captured Original together with its durable progress through transfer,
integrity verification, event linkage, and source clearance.
_Avoid_: upload item, queue entry

**Sync Lifecycle**:
The durable per-Sync-Item progression from discovery until the Captured
Original is either safely cleared or retained with an explicit reason.
_Avoid_: upload status, charging session

**Clearance Receipt**:
Durable end-to-end proof binding a Captured Original's SHA-256 and byte length
to its File Registry identity, event linkage, and backend acceptance. A
transfer response without all of these facts is not a Clearance Receipt.
_Avoid_: upload success, registration response

**Automatic Clearance**:
The default removal of a Captured Original after its Clearance Receipt has
been durably retained by the HydraCam device.
_Avoid_: delete after upload, cleanup

**Clearance Evaluation**:
The phone's comparison of a valid Clearance Receipt with the exact bytes and
identity of its local Captured Original. Fleet commands may request this
evaluation but cannot bypass or replace it.
_Avoid_: remote delete, forced cleanup

**Autonomous Sync**:
Sync that begins without operator confirmation when external power is present
and the device is Capture-Safe. Capture work always takes priority over it.
_Avoid_: background upload, unattended cleanup

**Capture-Safe**:
The condition in which a device is not recording or performing time-critical
capture coordination, so Sync may run without endangering the shoot.
_Avoid_: idle, unused

**Sync Now**:
An operator request to process eligible Sync Items as soon as the device is
Capture-Safe. It does not waive trust, integrity, attribution, or clearance
requirements.
_Avoid_: force upload, bypass

**Managed Fleet Phone**:
An enrolled Android phone under the device-management and operating policy
required for HydraCam's near-real-time background observability and control.
_Avoid_: connected phone, active device

**Fleet Enrollment**:
The organization- or venue-owned relationship that gives one Managed Fleet
Phone a unique, revocable device identity and defines who may control it.
_Avoid_: login, pairing, device registration

**Fleet Operator**:
An authenticated person or service granted a specific role for issuing audited
commands to enrolled phones.
_Avoid_: admin, logged-in user, phone owner

**Reduced-Control Phone**:
A supported phone, including iOS devices, whose platform does not provide the
Managed Fleet Phone control guarantee. Its Sync progress remains durable, but
remote command timing depends on platform-scheduled execution or foreground
use.
_Avoid_: unsupported phone, offline phone

**Device Sync State**:
The operator-facing rollup derived from every eligible Sync Item and the
device's current operating conditions.
_Avoid_: batch status, upload state

**Fully Charged**:
A battery qualifier indicating that charging has reached the product's full
threshold. It does not attest that Sync Items are safe, linked, or cleared.
_Avoid_: Ready, synced
