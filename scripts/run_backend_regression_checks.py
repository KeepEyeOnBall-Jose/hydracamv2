#!/usr/bin/env python3
"""Run backend-regression checks and persist machine-readable results."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "logs" / "backend_regression_results.json"


def run_command(cmd: list[str]) -> dict[str, object]:
    completed = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        check=False,
        text=True,
        capture_output=True,
    )
    return {
        "command": cmd,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def main() -> int:
    payload = {
        "backend_orchestrator_tests": run_command(
            [sys.executable, "scripts/test_multi_device_orchestrator_backend.py"]
        ),
        "backend_env_probe": run_command(
            [sys.executable, "scripts/check_backend_env.py"]
        ),
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(str(OUTPUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
