#!/usr/bin/env python3
"""Reconstruct a Camera2 HLS bundle from the base64 markers emitted by the
on-device proof (camera2_hls_proof_main.dart / hardware evidence test).

Usage: reconstruct_camera2_bundle.py <proof-log> <output-dir>
"""
import base64
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: reconstruct_camera2_bundle.py <proof-log> <output-dir>")
        return 64
    log_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    name = None
    buf: list[str] = []
    written = []
    for raw in log_path.read_text().splitlines():
        line = re.sub(r"^I/flutter \(\s*\d+\):\s*", "", raw).strip()
        if line.startswith("CAMERA2_FILE_BEGIN"):
            m = re.search(r"name=(\S+)", line)
            name = m.group(1) if m else None
            buf = []
        elif line.startswith("CAMERA2_B64"):
            buf.append(line.split(" ", 1)[1] if " " in line else "")
        elif line.startswith("CAMERA2_FILE_END"):
            if name is not None:
                data = base64.b64decode("".join(buf))
                (out_dir / name).write_bytes(data)
                written.append((name, len(data)))
            name = None
            buf = []

    if not written:
        print("No CAMERA2_FILE_* markers found in", log_path)
        return 1
    for n, size in written:
        print(f"wrote {n} ({size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
