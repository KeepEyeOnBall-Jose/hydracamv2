#!/usr/bin/env python3
"""Run backend-regression checks and persist machine-readable results.

Historically this existed as two near-identical scripts
(``run_backend_regression_checks.py`` and ``..._v2.py``) that differed only
in which JSON path they wrote to and which copy of the orchestrator test
file they invoked. The test files have since been merged into a single
``scripts/test_multi_device_orchestrator_backend.py``, so both suites now
run the same command; the only remaining difference is the output path.

Use ``--suite`` to pick which historical output path(s) to write:
  - ``default`` : logs/backend_regression_results.json      (original behavior)
  - ``v2``      : logs/backend_regression_results_v2.json    (v2 behavior)
  - ``both``    : write both paths from a single test run (default)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DEFAULT = REPO_ROOT / "logs" / "backend_regression_results.json"
OUTPUT_V2 = REPO_ROOT / "logs" / "backend_regression_results_v2.json"


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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--suite",
        choices=["default", "v2", "both"],
        default="both",
        help="Which historical output path(s) to write (default: both).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    payload = {
        "backend_orchestrator_tests": run_command(
            [sys.executable, "scripts/test_multi_device_orchestrator_backend.py"]
        ),
        "backend_env_probe": run_command(
            [sys.executable, "scripts/check_backend_env.py"]
        ),
    }
    serialized = json.dumps(payload, indent=2)

    outputs = {
        "default": [OUTPUT_DEFAULT],
        "v2": [OUTPUT_V2],
        "both": [OUTPUT_DEFAULT, OUTPUT_V2],
    }[args.suite]

    for output in outputs:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(serialized, encoding="utf-8")
        print(str(output))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
