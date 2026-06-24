#!/usr/bin/env python3
"""Upload a small multi-camera test set through the HydraCam legacy API."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import requests


REPO_ROOT = Path(__file__).resolve().parents[4]
API_BASE_URL = "https://hydracam.azurewebsites.net/api"
AUTH_SOURCE = REPO_ROOT / "lib" / "services" / "auth0_m2m_service.dart"


def read_dart_string(name: str) -> str:
    text = AUTH_SOURCE.read_text(encoding="utf-8")
    match = re.search(rf'final String _{name}\s*=\s*"([^"]+)";', text)
    if not match:
        raise RuntimeError(f"Unable to find _{name} in {AUTH_SOURCE}")
    return match.group(1)


def request_token() -> str:
    response = requests.post(
        read_dart_string("tokenUrl"),
        headers={"Content-Type": "application/json"},
        json={
            "client_id": read_dart_string("clientId"),
            "client_secret": read_dart_string("clientSecret"),
            "audience": read_dart_string("audience"),
            "grant_type": "client_credentials",
        },
        timeout=30,
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"Auth0 token request failed: {response.status_code} {response.text}"
        )
    token = response.json().get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Auth0 token response did not include access_token")
    return token


def ffprobe_duration_ms(path: Path) -> int:
    completed = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nokey=1:noprint_wrappers=1",
            str(path),
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    return int(float(completed.stdout.strip()) * 1000)


def create_session(token: str, *, session_id: str, court_guid: str | None) -> dict[str, Any]:
    response = requests.post(
        f"{API_BASE_URL}/sessions/create",
        params={"courtGuid": court_guid} if court_guid else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        json={
            "SessionId": session_id,
            "StartTime": dt.datetime.now(dt.timezone.utc).isoformat(),
        },
        timeout=60,
    )
    if response.status_code != 200:
        raise RuntimeError(
            f"Session create failed: {response.status_code} {response.text}"
        )
    payload = response.json()
    guid = str(payload.get("guid") or payload.get("Guid") or "").strip()
    if not guid:
        raise RuntimeError(f"Session create response missing guid: {payload}")
    return payload


def upload_video(
    token: str,
    *,
    session_guid: str,
    path: Path,
    device_id: str,
    captured_at: dt.datetime,
) -> dict[str, Any]:
    duration_ms = ffprobe_duration_ms(path)
    recording_end = captured_at + dt.timedelta(milliseconds=duration_ms)
    with path.open("rb") as handle:
        response = requests.post(
            f"{API_BASE_URL}/sessions/upload-media",
            params={"sessionGuid": session_guid, "isPhoto": "false"},
            headers={"Authorization": f"Bearer {token}"},
            data={
                "slaveDeviceId": device_id,
                "captureDate": captured_at.isoformat(),
                "receivedDate": recording_end.isoformat(),
                "recordingEndDate": recording_end.isoformat(),
                "durationMs": str(duration_ms),
                "appVersion": "codex-test-set",
                "appBuildNumber": "20260614",
            },
            files={"files": (path.name, handle, "video/mp4")},
            timeout=120,
        )
    if response.status_code != 200:
        raise RuntimeError(
            f"Upload failed for {path.name}: {response.status_code} {response.text}"
        )
    text = response.text.strip()
    try:
        payload: Any = response.json() if text else {"raw": text}
    except ValueError:
        payload = {"raw": text}
    if isinstance(payload, dict):
        lowered = str(
            payload.get("status")
            or payload.get("Status")
            or payload.get("message")
            or payload.get("Message")
            or ""
        ).lower()
        if payload.get("success") is False or "fail" in lowered or "error" in lowered:
            raise RuntimeError(f"Upload response reported failure for {path.name}: {payload}")
    return {
        "file": str(path),
        "filename": path.name,
        "deviceId": device_id,
        "durationMs": duration_ms,
        "statusCode": response.status_code,
        "response": payload,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-id", required=True)
    parser.add_argument("--court-guid")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("media", nargs="+", type=Path)
    args = parser.parse_args(argv)

    token = request_token()
    session = create_session(
        token,
        session_id=args.session_id,
        court_guid=args.court_guid,
    )
    session_guid = str(session.get("guid") or session.get("Guid"))
    numeric_id = session.get("id") or session.get("Id")
    started_at = dt.datetime.now(dt.timezone.utc)

    uploads = []
    for index, media_path in enumerate(args.media, start=1):
        uploads.append(
            upload_video(
                token,
                session_guid=session_guid,
                path=media_path,
                device_id=f"codex-test-camera-{index}",
                captured_at=started_at + dt.timedelta(seconds=index),
            )
        )

    result = {
        "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "apiBaseUrl": API_BASE_URL,
        "session": session,
        "sessionGuid": session_guid,
        "numericSessionId": numeric_id,
        "detailsUrl": (
            f"https://hydracam.azurewebsites.net/HydraCam/Details/{numeric_id}"
            if numeric_id is not None
            else None
        ),
        "uploads": uploads,
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "sessionGuid": session_guid,
        "numericSessionId": numeric_id,
        "uploadCount": len(uploads),
        "output": str(args.output),
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
