#!/usr/bin/env python3
"""Report whether backend verification environment variables are present."""

from __future__ import annotations

import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "logs" / "backend_env_status.json"


def main() -> int:
    payload = {
        "HYDRACAM_API_BASE": {
            "present": bool(os.getenv("HYDRACAM_API_BASE")),
        },
        "HYDRACAM_AUTOMATION_TOKEN": {
            "present": bool(os.getenv("HYDRACAM_AUTOMATION_TOKEN")),
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(str(OUTPUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
