#!/usr/bin/env python3
"""Contract: no CI job may depend only on an opportunistic host.

Madrid, the owned Macs/Windows box and IBM spot nodes may be busy, asleep or
gone; a job pinned to them turns a PR red or leaves it queued. Blocking jobs
route through CI_LINUX_RUNNER_LABELS (or hosted runners) instead.
"""

import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"
PINS = ("owned-", "keob-ibm-spot", "keob-host-", "trusted-owner")


def runs_on_values(text):
    """Each job's runs-on value, folded block scalars joined onto one line."""
    values = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"^(\s*)runs-on:\s*(.*)$", line)
        if not match:
            continue
        value, indent = match.group(2), len(match.group(1))
        if value in (">-", ">", "|", ""):
            body = []
            for follow in lines[i + 1:]:
                if follow.strip() and len(follow) - len(follow.lstrip()) <= indent:
                    break
                body.append(follow.strip())
            value = " ".join(body)
        values.append(value)
    return values


class CiRoutingTests(unittest.TestCase):
    def test_no_job_depends_only_on_an_opportunistic_host(self):
        for workflow in sorted(WORKFLOWS.glob("*.yml")):
            for value in runs_on_values(workflow.read_text()):
                with self.subTest(workflow=workflow.name, runs_on=value):
                    for pin in PINS:
                        self.assertNotIn(pin, value)

    def test_python_tests_use_the_routed_pool(self):
        values = runs_on_values((WORKFLOWS / "scripts-quality.yml").read_text())
        self.assertIn(
            "fromJSON(vars.CI_LINUX_RUNNER_LABELS || '[\"keob-linux-ci\",\"repo-hydracamv2\"]')",
            values[0],
        )


if __name__ == "__main__":
    unittest.main()
