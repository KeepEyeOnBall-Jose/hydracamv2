#!/usr/bin/env python3
"""Probe media-timeline direct object upload using the HydraCam bridge contract."""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

DEFAULT_API_BASE_URL = "http://127.0.0.1:3001/api"
DEFAULT_FILENAME_PREFIX = "hydracam-direct-upload-probe"
DEFAULT_DEVICE_ID = "codex-direct-upload-probe"
DEFAULT_MIME_TYPE = "image/jpeg"
DEFAULT_MEDIA_BYTES = (
    b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00\x01\x00\x01\x00\x00"
    b"\xff\xdb\x00C\x00" + bytes([8] * 64) + b"\xff\xd9"
)
SENSITIVE_KEYS = {
    "uploadToken",
    "UploadToken",
    "authorization",
    "Authorization",
}


class HttpStatusError(RuntimeError):
    def __init__(self, *, status: int, payload: object):
        super().__init__(f"HTTP {status}: {payload}")
        self.status = status
        self.payload = payload


RequestJson = Callable[..., object]


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


def api_path_url(api_base_url: str, path: str, query: dict[str, str] | None = None) -> str:
    if path.startswith("http://") or path.startswith("https://"):
        base = path
    elif path.startswith("/api/"):
        base = f"{root_base_url(api_base_url)}{path}"
    else:
        base = f"{normalize_api_base_url(api_base_url)}/{path.lstrip('/')}"
    if query:
        return f"{base}?{urlencode(query)}"
    return base


def request_json(
    method: str,
    url: str,
    *,
    json_body: object | None = None,
    bytes_body: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout_seconds: float = 10,
) -> object:
    normalized_method = method.upper()
    body: bytes | None = None
    request_headers = dict(headers or {})
    if json_body is not None:
        body = json.dumps(json_body).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")
    elif bytes_body is not None:
        body = bytes_body
        request_headers.setdefault("Content-Type", "application/octet-stream")
        request_headers.setdefault("Content-Length", str(len(bytes_body)))

    request = Request(
        url,
        data=body,
        method=normalized_method,
        headers=request_headers,
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


def build_probe_report(
    api_base_url: str,
    *,
    filename: str,
    media_bytes: bytes,
    mime_type: str,
    kind: str,
    device_id: str,
    request_json: RequestJson = request_json,
    timeout_seconds: float = 10,
) -> dict[str, Any]:
    api_base = normalize_api_base_url(api_base_url)
    checked_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    session_id = f"codex-direct-upload-{uuid.uuid4()}"
    captured_at = checked_at
    received_at = checked_at
    steps: list[dict[str, Any]] = []

    try:
        create_session = _step(
            steps,
            "createBridgeSession",
            request_json(
                "POST",
                api_path_url(api_base, "/api/hydracam-bridge/compat/sessions/create"),
                json_body={
                    "SessionId": session_id,
                    "StartTime": captured_at,
                },
                timeout_seconds=timeout_seconds,
            ),
        )
        session_guid = _required_string(
            _map_get(create_session, "guid", "sessionGuid"),
            "create session guid",
        )
        upload_token = _required_string(
            _map_get(create_session, "uploadToken", "UploadToken"),
            "create session uploadToken",
        )

        direct_start = _step(
            steps,
            "startBridgeDirectUpload",
            request_json(
                "POST",
                api_path_url(
                    api_base,
                    f"/api/hydracam-bridge/sessions/{session_guid}/uploads/start",
                ),
                json_body={
                    "filename": filename,
                    "kind": kind,
                    "deviceId": device_id,
                    "capturedAt": captured_at,
                    "receivedAt": received_at,
                    "size": len(media_bytes),
                    "mimeType": mime_type,
                },
                headers={"Authorization": f"Bearer {upload_token}"},
                timeout_seconds=timeout_seconds,
            ),
        )
        event_id = _required_string(_map_get(direct_start, "eventId"), "eventId")
        media_storage = _required_map(_map_get(direct_start, "mediaStorage"), "mediaStorage")

        multipart_start = _step(
            steps,
            "startMediaStorageMultipartUpload",
            request_json(
                "POST",
                api_path_url(api_base, _required_string(media_storage.get("startPath"), "startPath")),
                json_body={
                    "filename": filename,
                    "contentType": mime_type,
                    "eventId": event_id,
                },
                timeout_seconds=timeout_seconds,
            ),
        )
        key = _required_string(_map_get(multipart_start, "key"), "multipart key")
        upload_id = _required_string(_map_get(multipart_start, "uploadId"), "uploadId")

        uploaded_part = _step(
            steps,
            "uploadMediaStorageMultipartPart",
            request_json(
                "PUT",
                api_path_url(
                    api_base,
                    _required_string(media_storage.get("uploadPartPath"), "uploadPartPath"),
                    {
                        "key": key,
                        "uploadId": upload_id,
                        "partNumber": "1",
                    },
                ),
                bytes_body=media_bytes,
                timeout_seconds=timeout_seconds,
            ),
        )

        storage_complete = _step(
            steps,
            "completeMediaStorageMultipartUpload",
            request_json(
                "POST",
                api_path_url(
                    api_base,
                    _required_string(media_storage.get("completeObjectPath"), "completeObjectPath"),
                ),
                json_body={
                    "key": key,
                    "uploadId": upload_id,
                    "filename": filename,
                    "kind": kind,
                    "parts": [_part_json(uploaded_part)],
                },
                timeout_seconds=timeout_seconds,
            ),
        )
        locator = _required_string(_map_get(storage_complete, "locator"), "locator")
        registered = _required_map(_map_get(storage_complete, "registered"), "registered")
        file_id = _required_string(_map_get(registered, "fileId"), "registered.fileId")

        bridge_complete = _step(
            steps,
            "completeBridgeUpload",
            request_json(
                "POST",
                api_path_url(
                    api_base,
                    _required_string(media_storage.get("completeBridgePath"), "completeBridgePath"),
                ),
                json_body={
                    "fileId": file_id,
                    "locator": locator,
                    "metadata": {
                        "sessionGuid": session_guid,
                        "deviceId": device_id,
                        "filename": filename,
                        "kind": kind,
                        "mimeType": mime_type,
                        "sourceBytes": len(media_bytes),
                        "capturedAt": captured_at,
                        "receivedAt": received_at,
                    },
                },
                headers={"Authorization": f"Bearer {upload_token}"},
                timeout_seconds=timeout_seconds,
            ),
        )
        completed_file_id = _required_string(_map_get(bridge_complete, "fileId"), "completed fileId")

        status = _step(
            steps,
            "readBridgeSessionStatus",
            request_json(
                "GET",
                api_path_url(
                    api_base,
                    f"/api/hydracam-bridge/sessions/{session_guid}/status",
                ),
                timeout_seconds=timeout_seconds,
            ),
        )
        return _sanitize_report({
            "ok": True,
            "apiBaseUrl": api_base,
            "checkedAt": checked_at,
            "eventId": event_id,
            "sessionGuid": session_guid,
            "fileId": completed_file_id,
            "locator": locator,
            "status": status,
            "steps": steps,
        })
    except Exception as error:  # noqa: BLE001 - evidence script records failures.
        return _sanitize_report({
            "ok": False,
            "apiBaseUrl": api_base,
            "checkedAt": checked_at,
            "message": str(error),
            "steps": steps,
        })


def _step(steps: list[dict[str, Any]], name: str, payload: object) -> object:
    steps.append({"name": name, "status": "ok", "payload": payload})
    return payload


def _map_get(value: object, *keys: str) -> object:
    if not isinstance(value, dict):
        return None
    for key in keys:
        if key in value:
            return value[key]
    return None


def _required_string(value: object, label: str) -> str:
    if isinstance(value, str) and value:
        return value
    raise ValueError(f"missing {label}")


def _required_map(value: object, label: str) -> dict[str, object]:
    if isinstance(value, dict):
        return value
    raise ValueError(f"missing {label}")


def _part_json(value: object) -> dict[str, object]:
    part = _required_map(value, "uploaded part")
    return {
        "PartNumber": _map_get(part, "PartNumber", "partNumber"),
        "ETag": _map_get(part, "ETag", "etag"),
    }


def _sanitize_report(value: object) -> object:
    if isinstance(value, dict):
        return {
            key: "[redacted]" if key in SENSITIVE_KEYS else _sanitize_report(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_sanitize_report(item) for item in value]
    return value


def write_report(run_dir: Path, report: dict[str, Any]) -> dict[str, Path]:
    run_dir.mkdir(parents=True, exist_ok=True)
    json_path = run_dir / "media-timeline-direct-upload-probe.json"
    markdown_path = run_dir / "media-timeline-direct-upload-probe.md"
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    markdown_path.write_text(_format_markdown_report(report))
    return {
        "json": json_path,
        "markdown": markdown_path,
    }


def _format_markdown_report(report: dict[str, Any]) -> str:
    result = "PASS" if report.get("ok") is True else "FAIL"
    lines = [
        f"# media-timeline direct upload probe: {result}",
        "",
        f"- API base URL: `{report.get('apiBaseUrl')}`",
        f"- Checked at: `{report.get('checkedAt', 'unknown')}`",
    ]
    for key in ["eventId", "sessionGuid", "fileId", "locator", "message"]:
        if report.get(key):
            lines.append(f"- {key}: `{report[key]}`")
    lines.extend([
        "",
        "| Step | Status |",
        "| --- | --- |",
    ])
    for raw_step in report.get("steps", []):
        if isinstance(raw_step, dict):
            lines.append(
                f"| `{raw_step.get('name')}` | `{raw_step.get('status')}` |"
            )
    lines.append("")
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base-url", default=DEFAULT_API_BASE_URL)
    parser.add_argument("--filename")
    parser.add_argument("--device-id", default=DEFAULT_DEVICE_ID)
    parser.add_argument("--mime-type", default=DEFAULT_MIME_TYPE)
    parser.add_argument("--kind", choices=["photo", "video"], default="photo")
    parser.add_argument("--timeout-seconds", type=float, default=10)
    parser.add_argument("--run-dir", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    filename = args.filename or f"{DEFAULT_FILENAME_PREFIX}-{uuid.uuid4()}.jpg"
    report = build_probe_report(
        args.api_base_url,
        filename=filename,
        media_bytes=DEFAULT_MEDIA_BYTES,
        mime_type=args.mime_type,
        kind=args.kind,
        device_id=args.device_id,
        timeout_seconds=args.timeout_seconds,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    if args.run_dir is not None:
        write_report(args.run_dir, report)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
