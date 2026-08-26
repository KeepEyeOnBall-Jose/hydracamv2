"""Centralized lab/store environment constants for HydraCam scripts.

Historically, lab bridge IPs, expected Wi-Fi subnets, media-timeline URLs, FTP
ports, and public store URLs were hard-coded directly in individual scripts
and runbooks. This module gives them one documented, overridable home.

Precedence (highest first):
  1. A real OS environment variable with the given key.
  2. The matching ``KEY=value`` line in ``config/lab.env`` (if that file
     exists). Repo root is resolved relative to this file, not the CWD.
  3. The ``default`` argument passed to :func:`get` — always the same
     hard-coded value already used today, so behavior is unchanged when
     neither an env var nor a lab.env file is present.

This module is stdlib-only and does not mutate ``os.environ``. It is
consultative only right now: no existing script reads it yet. Migrating
callers to use it happens in a later phase; see AUTOMATION_RUNBOOK.md's
"Lab configuration" section.

Usage:

    from hydracam_lib import labconfig

    bridge_port = labconfig.get("HYDRACAM_BRIDGE_PORT", "4762")
    subnet = labconfig.get("HYDRACAM_LAB_SUBNET", "192.168.178.0/24")

Run directly for a smoke test / dump of resolved values:

    python3 scripts/hydracam_lib/labconfig.py
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Optional

_REPO_ROOT = Path(__file__).resolve().parents[2]
_LAB_ENV_PATH = _REPO_ROOT / "config" / "lab.env"

_cache: Optional[Dict[str, str]] = None
_cache_path: Optional[Path] = None


def _parse_env_file(path: Path) -> Dict[str, str]:
    """Parse simple KEY=value lines. Blank lines and '#' comments are skipped.

    Values are not shell-expanded or quote-stripped beyond a single layer of
    matching double or single quotes, matching typical .env conventions.
    """
    values: Dict[str, str] = {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        if key:
            values[key] = value
    return values


def _load_file_values(path: Path = _LAB_ENV_PATH) -> Dict[str, str]:
    global _cache, _cache_path
    if _cache is None or _cache_path != path:
        _cache = _parse_env_file(path)
        _cache_path = path
    return _cache


def get(key: str, default: str, *, lab_env_path: Optional[Path] = None) -> str:
    """Resolve a lab/store constant.

    Order: real environment variable > config/lab.env entry > default.
    """
    env_value = os.environ.get(key)
    if env_value is not None:
        return env_value

    path = lab_env_path if lab_env_path is not None else _LAB_ENV_PATH
    file_values = _load_file_values(path)
    if key in file_values:
        return file_values[key]

    return default


def reset_cache() -> None:
    """Clear the cached config/lab.env contents (mainly for tests)."""
    global _cache, _cache_path
    _cache = None
    _cache_path = None


if __name__ == "__main__":
    # Smoke test: print resolution for the documented keys, with and without
    # a config/lab.env file present, plus current OS env override state.
    defaults = {
        "HYDRACAM_BRIDGE_PORT": "4762",
        "HYDRACAM_LAB_BRIDGE_HOST": "192.168.178.104",
        "HYDRACAM_LAB_SUBNET": "192.168.178.0/24",
        "HYDRACAM_LAB_DEVICE_IP": "192.168.178.64",
        "HYDRACAM_MEDIA_TIMELINE_API_BASE_URL": "http://192.168.1.20:3001/api",
        "HYDRACAM_FTP_PORT": "2121",
        "HYDRACAM_PRIVACY_POLICY_URL": "https://store-site-ten.vercel.app/privacy.html",
        "HYDRACAM_SUPPORT_URL": "https://store-site-ten.vercel.app/support.html",
        "HYDRACAM_ACCOUNT_DELETION_URL": (
            "https://store-site-ten.vercel.app/account-deletion.html"
        ),
    }
    print(f"config/lab.env present: {_LAB_ENV_PATH.exists()} ({_LAB_ENV_PATH})")
    for key, default in defaults.items():
        print(f"  {key} = {get(key, default)!r}")
