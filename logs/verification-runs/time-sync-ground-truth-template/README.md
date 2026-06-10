# Clock-Sync Ground-Truth Verification Run — RESULTS TEMPLATE

> **This is an empty template. No real measurements are filled in.** Every
> `<FILL IN>` below is operator-required and must be completed from a real
> two-device capture on physical hardware. Do **not** treat the example sidecar
> files in this directory as evidence — they are clearly-labeled synthetic
> samples used only to demonstrate the analysis script.

Follow `docs/control/time-sync-ground-truth-protocol.md`. Copy this directory to
a new dated run directory under `logs/verification-runs/` (e.g.
`logs/verification-runs/<YYYYMMDD-HHMM>-time-sync-ground-truth/`) and fill it in
there.

## 1. Run identity

- Date / time (local): `<FILL IN>`
- Operator: `<FILL IN>`
- App version / build: `<FILL IN>`
- Session GUID: `<FILL IN>`

## 2. Devices and roles

| Role   | Device model | OS version | Device ID | Sync chip confidence at capture |
| ------ | ------------ | ---------- | --------- | ------------------------------- |
| Master | `<FILL IN>`  | `<FILL IN>`| `<FILL IN>` | `<FILL IN: green/yellow/red>` |
| Slave  | `<FILL IN>`  | `<FILL IN>`| `<FILL IN>` | `<FILL IN: green/yellow/red>` |

- Hotspot / LAN used (SSID or description): `<FILL IN>`
- Master WebSocket reachable from slave (port 4040): `<FILL IN: yes/no>`

## 3. Synchronized event

- Event source (flash / clap board / LED / other): `<FILL IN>`
- Number of events fired: `<FILL IN>`
- Notes on visibility in both frames: `<FILL IN>`

## 4. Captured media and observed event offsets

| Clip | Media path | `.sync.json` path | Observed event offset (seconds) |
| ---- | ---------- | ----------------- | ------------------------------- |
| A    | `<FILL IN>`| `<FILL IN>`       | `<FILL IN>` (use 0 for photos)  |
| B    | `<FILL IN>`| `<FILL IN>`       | `<FILL IN>` (use 0 for photos)  |

## 5. Sidecar contents (paste verbatim)

### Clip A `.sync.json`

```json
<FILL IN: paste the full contents of clip A's <media>.sync.json>
```

### Clip B `.sync.json`

```json
<FILL IN: paste the full contents of clip B's <media>.sync.json>
```

## 6. Analysis command and output

Command run:

```bash
<FILL IN: e.g.>
python3 scripts/analyze_sync_alignment.py \
  --clip-a <clipA.sync.json> --event-a <secondsA> \
  --clip-b <clipB.sync.json> --event-b <secondsB>
```

Full output (paste verbatim):

```text
<FILL IN: paste the complete script output, including the VERDICT line>
```

Exit code: `<FILL IN: 0 = PASS, 1 = FAIL, 2 = bad/missing input>`

## 7. Verdict

- Signed alignment error: `<FILL IN>` ms
- Combined uncertainty (RSS): `<FILL IN>` ms
- Margin (`|error| + uncertainty`): `<FILL IN>` ms (threshold 50 ms)
- Both clips green? `<FILL IN: yes/no>`
- **Final result: `<FILL IN: PASS / FAIL>`**

## 8. Notes / anomalies

`<FILL IN: anything notable — yellow/red confidence, retries, multi-event
cross-checks, frame-reading ambiguity, etc.>`

---

## Synthetic example files in this directory (NOT evidence)

These files exist only to demonstrate the analysis script. They contain
**synthetic / example data** (note the `EXAMPLE-SYNTHETIC` markers inside) and
must never be cited as a real measurement:

- `example-pass-clipA.sync.json` — synthetic master clip (green, offset 0).
- `example-pass-clipB.sync.json` — synthetic slave clip that aligns within
  tolerance (green).
- `example-fail-clipB.sync.json` — synthetic slave clip with a large skew and
  degraded (yellow) confidence.

Demonstration commands (these are reproducible against the synthetic files):

```bash
# Self-test (synthetic in-memory inputs):
python3 scripts/analyze_sync_alignment.py --self-test
# -> prints "self-test passed", exit 0

# PASS demonstration (synthetic):
python3 scripts/analyze_sync_alignment.py \
  --clip-a logs/verification-runs/time-sync-ground-truth-template/example-pass-clipA.sync.json --event-a 5.000 \
  --clip-b logs/verification-runs/time-sync-ground-truth-template/example-pass-clipB.sync.json --event-b 3.922
# -> VERDICT: PASS, exit 0

# FAIL demonstration (synthetic):
python3 scripts/analyze_sync_alignment.py \
  --clip-a logs/verification-runs/time-sync-ground-truth-template/example-pass-clipA.sync.json --event-a 5.000 \
  --clip-b logs/verification-runs/time-sync-ground-truth-template/example-fail-clipB.sync.json --event-b 3.790
# -> VERDICT: FAIL, exit 1
```
