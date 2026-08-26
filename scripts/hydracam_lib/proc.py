"""Subprocess runner shared by the Android probing scripts.

The scripts historically each carried a near-identical ``run_command`` that
wrapped :func:`subprocess.run` with ``text``/``capture_output`` and a timeout,
plus a ``checked_run`` that raised on a non-zero exit. Those live here now.
"""

from __future__ import annotations

import subprocess
from typing import Callable, NamedTuple, Sequence


class CommandResult(NamedTuple):
    returncode: int
    stdout: str
    stderr: str

    @property
    def combined_output(self) -> str:
        return "\n".join(part for part in (self.stdout, self.stderr) if part)


def run(command: Sequence[str], *, timeout: int, check: bool = False) -> CommandResult:
    """Run ``command`` and capture its output as a :class:`CommandResult`.

    With ``check=True`` a non-zero exit raises :class:`subprocess.CalledProcessError`,
    matching ``subprocess.run(..., check=True)``. The default ``check=False``
    always returns, letting callers inspect ``returncode`` themselves.
    """
    completed = subprocess.run(
        list(command),
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    result = CommandResult(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            list(command),
            output=result.stdout,
            stderr=result.stderr,
        )
    return result


def checked_run(
    command: Sequence[str],
    *,
    timeout: int,
    runner: Callable[..., CommandResult] = run,
) -> CommandResult:
    """Run ``command`` via ``runner`` and raise :class:`RuntimeError` on failure."""
    result = runner(list(command), timeout=timeout)
    if result.returncode != 0:
        printable = " ".join(command)
        raise RuntimeError(
            f"Command failed ({result.returncode}): {printable}\n"
            f"{result.combined_output}"
        )
    return result
