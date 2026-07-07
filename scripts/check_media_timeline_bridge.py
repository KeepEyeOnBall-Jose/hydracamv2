#!/usr/bin/env python3
"""Preflight media-timeline bridge readiness for HydraCam capture evidence."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

PROBE_SESSION_GUID = "00000000-0000-4000-8000-000000000000"
DEFAULT_API_BASE_URL = "http://127.0.0.1:3001/api"


class HttpStatusError(RuntimeError):
    def __init__(self, *, status: int, payload: object):
        super().__init__(f"HTTP {status}: {payload}")
        self.status = status
        self.payload = payload


FetchJson = Callable[..., object]


def normalize_api_base_url(value: str) -> str:
    normalized = value.strip().rstrip("/")
    if not normalized:
        raise ValueError("media-timeline API base URL is required")
    return normalized


def root_base_url(api_base_url: str) -> str:
    parsed = urlsplit(normalize_api_base_url(api_base_url))
    path = parsed.path.rstrip("/")
    if path.endswith("/api"):
        path = path[:-4]
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", "")).rstrip("/")


def fetch_json(
    url: str,
    *,
    method: str = "GET",
    timeout_seconds: float = 5,
) -> object:
    data = b"{}" if method.upper() != "GET" else None
    request = Request(
        url,
        data=data,
        method=method.upper(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            return _decode_response_payload(response.read())
    except HTTPError as error:
        raise HttpStatusError(
            status=error.code,
            payload=_decode_response_payload(error.read()),
        ) from error
    except URLError as error:
        raise RuntimeError(f"request failed: {error.reason}") from error


def _decode_response_payload(raw: bytes) -> object:
    if not raw:
        return {}
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return raw.decode("utf-8", errors="replace")


def build_preflight_report(
    api_base_url: str,
    *,
    fetch_json: FetchJson = fetch_json,
    timeout_seconds: float = 5,
) -> dict[str, Any]:
    api_base = normalize_api_base_url(api_base_url)
    checks = {
        "backendHealth": _check_backend_health(
            api_base,
            fetch_json=fetch_json,
            timeout_seconds=timeout_seconds,
        ),
        "mediaStorage": _check_media_storage(
            api_base,
            fetch_json=fetch_json,
            timeout_seconds=timeout_seconds,
        ),
        "directUploadRoute": _check_direct_upload_route(
            api_base,
            fetch_json=fetch_json,
            timeout_seconds=timeout_seconds,
        ),
    }
    return {
        "ok": all(check["status"] == "ok" for check in checks.values()),
        "apiBaseUrl": api_base,
        "checkedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "checks": checks,
    }


def _check_backend_health(
    api_base_url: str,
    *,
    fetch_json: FetchJson,
    timeout_seconds: float,
) -> dict[str, Any]:
    url = f"{root_base_url(api_base_url)}/health?deep=1"
    try:
        payload = fetch_json(url, method="GET", timeout_seconds=timeout_seconds)
        return {
            "status": "ok",
            "url": url,
            "payload": payload,
        }
    except Exception as error:  # noqa: BLE001 - evidence script records failures.
        return {
            "status": "blocked",
            "url": url,
            "message": str(error),
        }


def _check_media_storage(
    api_base_url: str,
    *,
    fetch_json: FetchJson,
    timeout_seconds: float,
) -> dict[str, Any]:
    url = f"{api_base_url}/media-storage/status"
    try:
        payload = fetch_json(url, method="GET", timeout_seconds=timeout_seconds)
        if not isinstance(payload, dict):
            return {
                "status": "blocked",
                "url": url,
                "message": "media-storage status returned a non-object payload",
                "payload": payload,
            }
        if payload.get("enabled") is not True:
            return {
                "status": "blocked",
                "url": url,
                "message": "object storage disabled",
                "provider": payload.get("provider"),
                "bucket": payload.get("bucket"),
                "payload": payload,
            }
        return {
            "status": "ok",
            "url": url,
            "provider": payload.get("provider"),
            "bucket": payload.get("bucket"),
            "signedUrlTtlSeconds": payload.get("signedUrlTtlSeconds"),
            "payload": payload,
        }
    except Exception as error:  # noqa: BLE001 - evidence script records failures.
        return {
            "status": "blocked",
            "url": url,
            "message": str(error),
        }


def _check_direct_upload_route(
    api_base_url: str,
    *,
    fetch_json: FetchJson,
    timeout_seconds: float,
) -> dict[str, Any]:
    url = (
        f"{api_base_url}/hydracam-bridge/sessions/"
        f"{PROBE_SESSION_GUID}/uploads/start"
    )
    try:
        payload = fetch_json(url, method="POST", timeout_seconds=timeout_seconds)
        return {
            "status": "blocked",
            "url": url,
            "message": "direct upload route unexpectedly accepted unauthenticated probe",
            "payload": payload,
        }
    except HttpStatusError as error:
        error_text = json.dumps(error.payload)
        if error.status == 401 and "Authorization" in error_text:
            return {
                "status": "ok",
                "url": url,
                "httpStatus": error.status,
                "payload": error.payload,
            }
        return {
            "status": "blocked",
            "url": url,
            "httpStatus": error.status,
            "message": error_text,
            "payload": error.payload,
        }
    except Exception as error:  # noqa: BLE001 - evidence script records failures.
        return {
            "status": "blocked",
            "url": url,
            "message": str(error),
        }


def write_report(run_dir: Path, report: dict[str, Any]) -> dict[str, Path]:
    run_dir.mkdir(parents=True, exist_ok=True)
    json_path = run_dir / "media-timeline-bridge-preflight.json"
    markdown_path = run_dir / "media-timeline-bridge-preflight.md"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    markdown_path.write_text(_format_markdown_report(report))
    return {
        "json": json_path,
        "markdown": markdown_path,
    }


def _format_markdown_report(report: dict[str, Any]) -> str:
    result = "PASS" if report.get("ok") is True else "FAIL"
    lines = [
        f"# media-timeline bridge preflight: {result}",
        "",
        f"- API base URL: `{report.get('apiBaseUrl')}`",
        f"- Checked at: `{report.get('checkedAt', 'unknown')}`",
        "",
        "| Check | Status | Detail |",
        "| --- | --- | --- |",
    ]
    checks = report.get("checks", {})
    if isinstance(checks, dict):
        for name, raw_check in checks.items():
            check = raw_check if isinstance(raw_check, dict) else {}
            detail = check.get("message") or check.get("provider") or check.get("httpStatus") or ""
            lines.append(f"| `{name}` | `{check.get('status')}` | `{detail}` |")
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base-url", default=DEFAULT_API_BASE_URL)
    parser.add_argument("--timeout-seconds", type=float, default=5)
    parser.add_argument("--run-dir", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    report = build_preflight_report(
        args.api_base_url,
        timeout_seconds=args.timeout_seconds,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    if args.run_dir is not None:
        write_report(args.run_dir, report)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
