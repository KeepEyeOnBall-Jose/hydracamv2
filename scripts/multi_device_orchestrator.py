#!/usr/bin/env python3
"""HydraCam multi-device orchestration entrypoint."""

from __future__ import annotations

# Ensure project root is on sys.path so this script can be run directly
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import requests
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, cast
from urllib.parse import urlparse

# optional emulator control helpers
from scripts.emulator_manager import EmulatorManager

AUTOMATION_REMOTE_PORT = 4762
DEFAULT_PORT_BASE = 5900
HTTP_TIMEOUT_SECONDS = 120
PLACEHOLDER_PATTERN: re.Pattern[str] = re.compile(
    r"{{\s*([a-zA-Z0-9_.-]+)\s*}}",
)


@dataclass
class DeviceTarget:
    """Represents a single emulator/physical device under orchestration."""

    serial: str
    role: str
    local_port: int
    name: str


Descriptor = Dict[str, str]


class OrchestratorError(RuntimeError):
    """Raised when automation orchestration fails."""


class MultiDeviceOrchestrator:
    def __init__(
        self,
        devices: List[DeviceTarget],
        *,
        dry_run: bool = False,
        manifest: Optional[Path] = None,
        scenario: str = "smoke",
        output_root: Path,
        backend_base_url: Optional[str],
        backend_token: Optional[str],
    ) -> None:
        self.devices = devices
        self.dry_run = dry_run
        self.manifest = manifest
        self.scenario = scenario
        self.output_root = output_root
        self.backend_base_url = (
            backend_base_url.rstrip("/") if backend_base_url else None
        )
        self.backend_token = backend_token
        self.run_dir: Optional[Path] = None
        now = dt.datetime.now(dt.timezone.utc)
        self.context: Dict[str, Any] = {
            "timestamp": int(now.timestamp()),
            "isoTimestamp": now.isoformat(),
            "scenario": scenario,
        }
        self._cached_manifest: Optional[Dict[str, Any]] = None
        self.summary_stub: Dict[str, object] = {
            "scenario": scenario,
            "dryRun": dry_run,
            "devices": [
                {
                    "serial": device.serial,
                    "role": device.role,
                    "name": device.name,
                    "localPort": device.local_port,
                }
                for device in devices
            ],
        }

    def run(self) -> None:
        if not self.devices:
            raise OrchestratorError(
                "No devices available for orchestration",
            )

        scenario_result: Optional[Dict[str, object]] = None
        device_artifacts: Optional[List[Dict[str, object]]] = None
        backend_report: Optional[Dict[str, object]] = None
        started_at = time.time()
        self._prepare_run_directory()
        self._log(
            "Preparing %s device(s) for scenario '%s'",
            len(self.devices),
            self.scenario,
        )
        try:
            self._forward_ports()
            if self.dry_run:
                self._log(
                    "Dry-run complete (skipped health checks "
                    "and scenario execution)",
                )
                return

            self._await_health()
            scenario_result = self._run_scenario()
            device_artifacts = self._collect_device_artifacts()
            backend_report = self._run_backend_verification(scenario_result)
        finally:
            self._write_summary(
                started_at,
                scenario_result,
                device_artifacts,
                backend_report,
            )

    # ------------------------------------------------------------------
    # Scenario execution
    # ------------------------------------------------------------------

    def _run_scenario(self) -> Dict[str, Any]:
        scenario = self.scenario.lower()
        if self.manifest:
            return self._run_manifest_scenario()
        if scenario == "smoke":
            return self._run_smoke_scenario()
        raise OrchestratorError(f"Unknown scenario '{self.scenario}'")

    def _run_smoke_scenario(self) -> Dict[str, Any]:
        master = self._get_master()
        if master is None:
            raise OrchestratorError(
                "Smoke scenario requires at least one master device",
            )

        payload: Dict[str, object] = {
            "sessionId": f"automation-{int(time.time())}",
        }
        self._log("Triggering session start on master %s", master.serial)
        start_response = self._post(master, "/commands/start_session", payload)
        self._log(
            "Start-session result: %s",
            json.dumps(start_response, indent=2),
        )

        self._log("Requesting immediate photo capture")
        photo_response = self._post(
            master,
            "/commands/take_photo",
            {"showCountdown": False},
        )
        self._log(
            "Photo command acknowledged: %s",
            json.dumps(photo_response, indent=2),
        )

        self._log("Stopping session")
        stop_response = self._post(master, "/commands/end_session", {})
        self._log(
            "End-session result: %s",
            json.dumps(stop_response, indent=2),
        )

        session_state = self._get(master, "/session")
        return {
            "sessionGuid": session_state.get("sessionGuid"),
            "commands": [
                {"name": "start_session", "response": start_response},
                {"name": "take_photo", "response": photo_response},
                {"name": "end_session", "response": stop_response},
            ],
            "finalSessionState": session_state,
        }

    # ------------------------------------------------------------------
    # Device helpers
    # ------------------------------------------------------------------

    def _forward_ports(self) -> None:
        for device in self.devices:
            cmd = [
                "adb",
                "-s",
                device.serial,
                "forward",
                f"tcp:{device.local_port}",
                f"tcp:{AUTOMATION_REMOTE_PORT}",
            ]
            self._log(
                "Forwarding %s => localhost:%s",
                device.serial,
                device.local_port,
            )
            self._run(cmd)

    def _await_health(self) -> None:
        for device in self.devices:
            self._log("Awaiting automation health for %s", device.serial)
            deadline = time.time() + 60
            while time.time() < deadline:
                try:
                    health = self._get(device, "/healthz")
                except OrchestratorError:
                    time.sleep(1)
                    continue

                if health.get("status") == "ok":
                    self._log("Device %s automation ready", device.serial)
                    break
            else:
                raise OrchestratorError(
                    "Automation bridge not reachable on %s (port %s)"
                    % (
                        device.serial,
                        device.local_port,
                    ),
                )

    def _get_master(self) -> Optional[DeviceTarget]:
        for device in self.devices:
            if device.role.lower() == "master":
                return device
        return None

    def _prepare_run_directory(self) -> None:
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        slug = f"{timestamp}-{self.scenario}"
        self.output_root.mkdir(parents=True, exist_ok=True)
        candidate = self.output_root / slug
        suffix = 1
        while candidate.exists():
            candidate = self.output_root / f"{slug}-{suffix}"
            suffix += 1
        candidate.mkdir(parents=True)
        self.run_dir = candidate
        self.context["runDir"] = str(candidate)
        devices_path = self.run_dir / "devices.json"
        devices_path.write_text(
            json.dumps(self.summary_stub["devices"], indent=2),
            encoding="utf-8",
        )
        self._log("Artifacts will be stored under %s", self.run_dir)

    def _load_manifest(self) -> Dict[str, Any]:
        if not self.manifest:
            raise OrchestratorError("Manifest path not provided")
        if self._cached_manifest is not None:
            return self._cached_manifest
        if not self.manifest.exists():
            raise OrchestratorError(
                f"Manifest file {self.manifest} does not exist",
            )
        try:
            content = self.manifest.read_text(encoding="utf-8")
            manifest = json.loads(content)
        except (OSError, json.JSONDecodeError) as exc:
            raise OrchestratorError(
                f"Failed to load manifest {self.manifest}: {exc}",
            ) from exc
        steps = manifest.get("steps")
        if not isinstance(steps, list) or not steps:
            raise OrchestratorError(
                ("Manifest %s must include a non-empty 'steps' array" % self.manifest),
            )
        manifest_context = manifest.get("context")
        if isinstance(manifest_context, Mapping):
            rendered_context = self._render_value(manifest_context)
            if not isinstance(rendered_context, Mapping):
                raise OrchestratorError(
                    "Manifest context must resolve to an object",
                )
            context_mapping = cast(Mapping[str, Any], rendered_context)
            rendered_map: Dict[str, Any] = {}
            for key, value in context_mapping.items():
                rendered_map[str(key)] = value
            self.context.update(rendered_map)
        self._cached_manifest = manifest
        return manifest

    def _run_manifest_scenario(self) -> Dict[str, Any]:
        manifest = self._load_manifest()
        steps = manifest["steps"]
        manifest_info: Dict[str, Any] = {
            "path": str(self.manifest),
            "name": manifest.get("name"),
            "description": manifest.get("description"),
        }
        handlers = {
            "command": self._manifest_step_command,
            "settings": self._manifest_step_settings,
            "get": self._manifest_step_get,
            "await": self._manifest_step_await,
            "sleep": self._manifest_step_sleep,
            "setContext": self._manifest_step_set_context,
        }
        results: List[Dict[str, Any]] = []
        for index, raw_step in enumerate(steps):
            if not isinstance(raw_step, Mapping):
                raise OrchestratorError(
                    f"Manifest step #{index + 1} must be an object",
                )
            step = cast(Mapping[str, Any], raw_step)
            action = step.get("action")
            if not isinstance(action, str):
                raise OrchestratorError(
                    f"Manifest step #{index + 1} is missing an 'action' field",
                )
            handler = handlers.get(action)
            if handler is None:
                raise OrchestratorError(
                    f"Unsupported manifest action '{action}'",
                )
            label = step.get("name") or step.get("label")
            if not label:
                label = f"step_{index + 1}"
            self._log("Executing manifest step %s (%s)", label, action)
            step_result = handler(step)
            results.append(
                {
                    "index": index,
                    "name": label,
                    "action": action,
                    "result": step_result,
                }
            )
        scenario_guid = self.context.get("sessionGuid")
        if isinstance(scenario_guid, str) and scenario_guid:
            session_guid_value = scenario_guid
        else:
            session_guid_value = None
        return {
            "manifest": manifest_info,
            "steps": results,
            "sessionGuid": session_guid_value,
        }

    def _manifest_step_command(
        self,
        step: Mapping[str, Any],
    ) -> Dict[str, Any]:
        command = step.get("command")
        if not isinstance(command, str) or not command:
            raise OrchestratorError("Manifest command step requires 'command'")
        payload_raw = self._ensure_mapping(
            step.get("payload", {}),
            "command payload",
        )
        payload = cast(Dict[str, Any], self._render_value(payload_raw))
        targets = self._select_targets(step, default_to_master=True)
        responses: List[Dict[str, Any]] = []
        for device in targets:
            response = self._post_with_retry(
                device,
                f"/commands/{command}",
                payload,
                command,
            )
            responses.append({"serial": device.serial, "response": response})
            capture_cfg = step.get("capture")
            if capture_cfg is not None:
                capture_map = self._ensure_mapping(
                    capture_cfg,
                    "command capture",
                )
                self._capture_from_payload(response, capture_map)
            if command == "start_session":
                session_guid = response.get("sessionGuid")
                if isinstance(session_guid, str) and session_guid:
                    self.context.setdefault("sessionGuid", session_guid)
        return {
            "command": command,
            "targets": [device.serial for device in targets],
            "payload": payload,
            "responses": responses,
        }

    def _manifest_step_settings(
        self,
        step: Mapping[str, Any],
    ) -> Dict[str, Any]:
        payload_raw = self._ensure_mapping(
            step.get("payload"),
            "settings payload",
        )
        payload = cast(Dict[str, Any], self._render_value(payload_raw))
        targets = self._select_targets(
            step,
            default_to_master=False,
            allow_all=True,
        )
        responses: List[Dict[str, Any]] = []
        for device in targets:
            response = self._post(device, "/settings", payload)
            responses.append({"serial": device.serial, "response": response})
        return {
            "targets": [device.serial for device in targets],
            "payload": payload,
            "responses": responses,
        }

    def _manifest_step_get(self, step: Mapping[str, Any]) -> Dict[str, Any]:
        path = step.get("path")
        if not isinstance(path, str) or not path.startswith("/"):
            raise OrchestratorError(
                "GET step requires a 'path' starting with /",
            )
        targets = self._select_targets(step, default_to_master=True)
        snapshots: List[Dict[str, Any]] = []
        for device in targets:
            payload = self._get(device, path)
            capture_cfg = step.get("capture")
            if capture_cfg is not None:
                capture_map = self._ensure_mapping(
                    capture_cfg,
                    "get capture",
                )
                self._capture_from_payload(payload, capture_map)
            snapshots.append({"serial": device.serial, "payload": payload})
        return {
            "path": path,
            "targets": [d.serial for d in targets],
            "payloads": snapshots,
        }

    def _manifest_step_await(self, step: Mapping[str, Any]) -> Dict[str, Any]:
        path = step.get("path")
        if not isinstance(path, str) or not path.startswith("/"):
            raise OrchestratorError(
                "Await step requires a 'path' starting with /",
            )
        expect = self._ensure_mapping(step.get("expect"), "await expect")
        timeout = float(step.get("timeoutSec", 30.0))
        interval = float(step.get("intervalSec", 1.0))
        targets = self._select_targets(step, default_to_master=True)
        fulfilled: List[Dict[str, Any]] = []
        for device in targets:
            payload = self._await_expectation(
                device,
                path,
                expect,
                timeout,
                interval,
            )
            fulfilled.append({"serial": device.serial, "payload": payload})
        return {
            "path": path,
            "targets": [device.serial for device in targets],
            "timeoutSec": timeout,
            "intervalSec": interval,
            "result": fulfilled,
        }

    def _manifest_step_sleep(self, step: Mapping[str, Any]) -> Dict[str, Any]:
        seconds = float(step.get("seconds", 1.0))
        self._log("Sleeping for %.2f second(s)", seconds)
        time.sleep(seconds)
        return {"slept": seconds}

    def _manifest_step_set_context(
        self,
        step: Mapping[str, Any],
    ) -> Dict[str, Any]:
        values = self._ensure_mapping(step.get("values"), "setContext values")
        rendered = self._render_value(values)
        if not isinstance(rendered, Mapping):
            raise OrchestratorError(
                "setContext values must resolve to an object",
            )
        rendered_mapping = cast(Mapping[str, Any], rendered)
        rendered_map: Dict[str, Any] = {}
        for key, value in rendered_mapping.items():
            rendered_map[str(key)] = value
        self.context.update(rendered_map)
        return {"context": dict(rendered_map)}

    def _capture_from_payload(
        self,
        payload: Mapping[str, Any],
        capture_cfg: Mapping[str, Any],
    ) -> None:
        for context_key, raw_path in capture_cfg.items():
            key_str = str(context_key)
            if not isinstance(raw_path, str):
                continue
            value = self._extract_path(payload, raw_path)
            if value is not None:
                self.context[key_str] = value

    def _await_expectation(
        self,
        device: DeviceTarget,
        path: str,
        expect: Mapping[str, Any],
        timeout: float,
        interval: float,
    ) -> Dict[str, Any]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            payload = self._get(device, path)
            if self._matches_expectation(payload, expect):
                capture_cfg = expect.get("capture")
                if capture_cfg is not None:
                    capture_map = self._ensure_mapping(
                        capture_cfg,
                        "await capture",
                    )
                    self._capture_from_payload(payload, capture_map)
                return payload
            time.sleep(interval)
        raise OrchestratorError(
            f"Await step timed out after {timeout:.1f}s on {device.serial}",
        )

    def _matches_expectation(
        self,
        payload: Mapping[str, Any],
        expect: Mapping[str, Any],
    ) -> bool:
        path = expect.get("path")
        if not isinstance(path, str):
            return False
        actual = self._extract_path(payload, path)
        if "equals" in expect:
            return actual == expect.get("equals")
        if "notEquals" in expect:
            return actual != expect.get("notEquals")
        if "contains" in expect:
            needle = expect.get("contains")
            if isinstance(actual, list):
                return needle in actual
            if isinstance(actual, str) and isinstance(needle, str):
                return needle in actual
        if "exists" in expect:
            should_exist = bool(expect.get("exists"))
            exists = actual is not None
            return exists if should_exist else not exists
        if "truthy" in expect:
            should_be_truthy = bool(expect.get("truthy"))
            return bool(actual) == should_be_truthy
        return False

    def _extract_path(self, payload: Any, path: str) -> Any:
        current: Any = payload
        for raw_part in path.split("."):
            part = raw_part.strip()
            if part == "":
                continue
            if isinstance(current, Mapping):
                mapping_current = cast(Mapping[str, Any], current)
                current = mapping_current.get(part)
            elif isinstance(current, list):
                try:
                    index = int(part)
                except ValueError:
                    return None
                list_current = cast(List[Any], current)
                if 0 <= index < len(list_current):
                    current = list_current[index]
                else:
                    return None
            else:
                return None
        return current

    def _select_targets(
        self,
        step: Mapping[str, Any],
        *,
        default_to_master: bool,
        allow_all: bool = False,
    ) -> List[DeviceTarget]:
        selected: List[DeviceTarget] = []
        serials: List[str] = []
        roles: List[str] = []
        serial_value = step.get("serial")
        if isinstance(serial_value, str):
            serials.append(serial_value)
        serials_value = step.get("serials")
        if isinstance(serials_value, list):
            serials_list = cast(List[Any], serials_value)
            for entry in serials_list:
                serials.append(str(entry))
        role_value = step.get("role")
        if isinstance(role_value, str):
            roles.append(role_value)
        roles_value = step.get("roles")
        if isinstance(roles_value, list):
            roles_list = cast(List[Any], roles_value)
            for entry in roles_list:
                roles.append(str(entry))
        if step.get("targets") == "all" and allow_all:
            selected = list(self.devices)
        else:
            if serials:
                for serial in serials:
                    device = self._find_device_by_serial(serial)
                    if device and device not in selected:
                        selected.append(device)
            if roles:
                for role in roles:
                    role_lower = role.lower()
                    for device in self.devices:
                        if device.role.lower() == role_lower:
                            if device not in selected:
                                selected.append(device)
        if not selected:
            if allow_all and step.get("targets") == "all":
                selected = list(self.devices)
        if not selected and default_to_master:
            master = self._get_master()
            if master is None:
                raise OrchestratorError(
                    "Manifest step requires a master device",
                )
            selected = [master]
        if not selected:
            raise OrchestratorError(
                "Manifest step requires at least one target device",
            )
        return selected

    def _find_device_by_serial(self, serial: str) -> Optional[DeviceTarget]:
        for device in self.devices:
            if device.serial == serial:
                return device
        return None

    def _render_value(self, value: Any) -> Any:
        if isinstance(value, str):
            return self._render_string(value)
        if isinstance(value, list):
            list_value = cast(List[Any], value)
            rendered_list: List[Any] = []
            for item in list_value:
                rendered_list.append(self._render_value(item))
            return rendered_list
        if isinstance(value, Mapping):
            mapping_value = cast(Mapping[str, Any], value)
            rendered_dict: Dict[str, Any] = {}
            for key, val in mapping_value.items():
                rendered_dict[str(key)] = self._render_value(val)
            return rendered_dict
        return value

    def _render_string(self, value: str) -> str:
        def _replacement(match: re.Match[str]) -> str:
            key = match.group(1)
            replacement = self.context.get(key)
            if replacement is not None:
                return str(replacement)
            return match.group(0)

        return PLACEHOLDER_PATTERN.sub(_replacement, value)

    def _ensure_mapping(
        self,
        value: Any,
        label: str,
    ) -> Mapping[str, Any]:
        if not isinstance(value, Mapping):
            raise OrchestratorError(f"{label} must be an object")
        return cast(Mapping[str, Any], value)

    def _collect_device_artifacts(self) -> List[Dict[str, Any]]:
        if not self.run_dir:
            return []
        snapshots: List[Dict[str, object]] = []
        for device in self.devices:
            device_dir = self.run_dir / device.serial
            device_dir.mkdir(parents=True, exist_ok=True)
            session_state = self._get(device, "/session")
            logs = self._get(device, "/logs")
            logs_field = logs.get("logs")
            if isinstance(logs_field, list):
                log_entries = cast(List[Any], logs_field)
            else:
                log_entries = []
            (device_dir / "session.json").write_text(
                json.dumps(session_state, indent=2),
                encoding="utf-8",
            )
            (device_dir / "logs.json").write_text(
                json.dumps(logs, indent=2),
                encoding="utf-8",
            )
            snapshots.append(
                {
                    "serial": device.serial,
                    "role": device.role,
                    "session": session_state,
                    "logCount": len(log_entries),
                }
            )
        return snapshots

    def _run_backend_verification(
        self, scenario_result: Optional[Dict[str, Any]]
    ) -> Optional[Dict[str, Any]]:
        if not scenario_result:
            return None
        session_guid_value = scenario_result.get("sessionGuid")
        if not isinstance(session_guid_value, str) or not session_guid_value:
            self._log("Skipping backend verification (session guid missing)")
            return None
        session_guid = session_guid_value
        if not self.backend_base_url or not self.backend_token:
            self._log(
                "Skipping backend verification "
                "(backend base URL/token not provided)",
            )
            return None

        backend_dir = self._ensure_backend_dir()
        session_payload = self._fetch_backend_session(session_guid)
        (backend_dir / "session.json").write_text(
            json.dumps(session_payload, indent=2),
            encoding="utf-8",
        )
        assets = self._extract_backend_assets(session_payload)
        downloads: List[Dict[str, Any]] = []
        for idx, asset in enumerate(assets):
            url = asset["url"]
            download = self._download_backend_asset(url, backend_dir, idx)
            downloads.append(download)
        report: Dict[str, Any] = {
            "sessionGuid": session_guid,
            "endpoint": f"{self.backend_base_url}/sessions/{session_guid}",
            "assetCount": len(assets),
            "downloads": downloads,
        }
        self._log(
            "Backend verification complete: %s asset(s) downloaded",
            len(downloads),
        )
        return report

    def _ensure_backend_dir(self) -> Path:
        if not self.run_dir:
            raise OrchestratorError("Run directory not initialized")
        backend_dir = self.run_dir / "backend"
        backend_dir.mkdir(parents=True, exist_ok=True)
        return backend_dir

    def _fetch_backend_session(self, session_guid: str) -> Dict[str, object]:
        url = f"{self.backend_base_url}/sessions/{session_guid}"
        headers = {
            "Authorization": f"Bearer {self.backend_token}",
            "Accept": "application/json",
        }
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                body = response.read().decode("utf-8")
        except urllib.error.URLError as exc:  # pragma: no cover
            raise OrchestratorError(
                f"Failed to fetch backend session {session_guid}: {exc}",
            ) from exc
        return json.loads(body)

    def _extract_backend_assets(
        self, payload: Mapping[str, Any]
    ) -> List[Dict[str, str]]:
        assets: List[Dict[str, str]] = []
        candidate_keys = ["assets", "materials", "media", "captures"]
        for key in candidate_keys:
            raw = payload.get(key)
            if isinstance(raw, list):
                raw_entries = cast(List[Any], raw)
                for entry in raw_entries:
                    if isinstance(entry, Mapping):
                        entry_map = cast(Mapping[str, Any], entry)
                        download_url = entry_map.get("downloadUrl")
                        fallback_url = entry_map.get("url")
                        url_candidate = download_url or fallback_url
                        if isinstance(url_candidate, str) and url_candidate:
                            assets.append({"url": url_candidate})
        # Some APIs might flatten into `uploads` object keyed by guid
        uploads = payload.get("uploads")
        if isinstance(uploads, Mapping):
            uploads_map = cast(Mapping[str, Any], uploads)
            for entry in uploads_map.values():
                if isinstance(entry, Mapping):
                    entry_map = cast(Mapping[str, Any], entry)
                    download_url = entry_map.get("downloadUrl")
                    fallback_url = entry_map.get("url")
                    url_candidate = download_url or fallback_url
                    if isinstance(url_candidate, str) and url_candidate:
                        assets.append({"url": url_candidate})
        return assets

    def _download_backend_asset(
        self, url: str, backend_dir: Path, idx: int
    ) -> Dict[str, Any]:
        parsed = urlparse(url)
        filename = Path(parsed.path).name or f"asset_{idx}"
        destination = backend_dir / filename
        headers = {"Authorization": f"Bearer {self.backend_token}"}
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                data = response.read()
        except urllib.error.URLError as exc:  # pragma: no cover
            raise OrchestratorError(
                f"Failed to download backend asset {url}: {exc}",
            ) from exc
        destination.write_bytes(data)
        sha256 = hashlib.sha256(data).hexdigest()
        return {
            "url": url,
            "file": str(destination),
            "bytes": len(data),
            "sha256": sha256,
        }

    def _write_summary(
        self,
        started_at: float,
        scenario_result: Optional[Dict[str, Any]],
        device_artifacts: Optional[List[Dict[str, Any]]],
        backend_report: Optional[Dict[str, Any]],
    ) -> None:
        if not self.run_dir:
            return
        finished_at = dt.datetime.now(dt.timezone.utc).isoformat()
        payload: Dict[str, Any] = {
            "scenario": self.scenario,
            "dryRun": self.dry_run,
            "startedAt": dt.datetime.fromtimestamp(
                started_at, tz=dt.timezone.utc
            ).isoformat(),
            "finishedAt": finished_at,
            "devices": self.summary_stub["devices"],
            "scenarioResult": scenario_result,
            "deviceSnapshots": device_artifacts,
            "backendReport": backend_report,
        }
        (self.run_dir / "summary.json").write_text(
            json.dumps(payload, indent=2),
            encoding="utf-8",
        )

    # ------------------------------------------------------------------
    # HTTP helpers
    # ------------------------------------------------------------------

    def _build_url(self, device: DeviceTarget, path: str) -> str:
        return f"http://127.0.0.1:{device.local_port}{path}"

    def _get(self, device: DeviceTarget, path: str) -> Dict[str, object]:
        return self._request(device, path, method="GET")

    def _post(
        self,
        device: DeviceTarget,
        path: str,
        payload: Mapping[str, object],
    ) -> Dict[str, object]:
        return self._request(device, path, method="POST", payload=payload)

    def _post_with_retry(
        self,
        device: DeviceTarget,
        path: str,
        payload: Mapping[str, object],
        command: str,
        retries: int = 5,
        delay_seconds: float = 3.0,
    ) -> Dict[str, object]:
        last_error: Optional[Exception] = None
        for attempt in range(1, retries + 1):
            try:
                return self._post(device, path, payload)
            except OrchestratorError as exc:
                last_error = exc
                if not self._is_retryable_error(exc) or attempt == retries:
                    raise
                self._log(
                    (
                        "Command %s on %s failed (%s) (attempt %d/%d). "
                        "Retrying in %.1fs..."
                    ),
                    command,
                    device.serial,
                    self._describe_error(exc),
                    attempt,
                    retries,
                    delay_seconds,
                )
                time.sleep(delay_seconds)
        raise OrchestratorError(
            "Command %s failed on %s after %d attempts"
            % (command, device.serial, retries)
        ) from last_error

    def _is_retryable_error(self, error: OrchestratorError) -> bool:
        cause = getattr(error, "__cause__", None)
        if isinstance(cause, urllib.error.HTTPError):
            return cause.code == 404
        if isinstance(cause, TimeoutError):
            return True
        if isinstance(cause, urllib.error.URLError):
            if isinstance(getattr(cause, "reason", None), TimeoutError):
                return True
        text = str(error).lower()
        return "404" in text or "timed out" in text

    def _describe_error(self, error: OrchestratorError) -> str:
        cause = getattr(error, "__cause__", None)
        if cause is not None:
            return str(cause)
        return str(error)

    def _request(
        self,
        device: DeviceTarget,
        path: str,
        *,
        method: str,
        payload: Optional[Mapping[str, object]] = None,
    ) -> Dict[str, object]:
        url = self._build_url(device, path)
        headers = {"Content-Type": "application/json"}
        try:
            if method == "GET":
                response = requests.get(
                    url,
                    headers=headers,
                    timeout=HTTP_TIMEOUT_SECONDS,
                )
            elif method == "POST":
                response = requests.post(
                    url,
                    json=payload if payload else {},
                    headers=headers,
                    timeout=HTTP_TIMEOUT_SECONDS,
                )
            else:
                raise OrchestratorError(f"Unsupported HTTP method: {method}")
            response.raise_for_status()
            return response.json() if response.text else {}
        except (
            requests.RequestException,
            ConnectionError,
            TimeoutError,
        ) as exc:  # pragma: no cover
            raise OrchestratorError(
                f"HTTP {method} {url} failed: {exc}",
            ) from exc

    # ------------------------------------------------------------------
    # Process helpers
    # ------------------------------------------------------------------

    def _run(self, cmd: List[str]) -> None:
        try:
            subprocess.run(
                cmd,
                check=True,
                capture_output=not sys.stdout.isatty(),
            )
        except subprocess.CalledProcessError as exc:
            joined = " ".join(cmd)
            raise OrchestratorError(
                (f"Command failed (exit {exc.returncode}): {joined}\n" f"{exc.stderr}"),
            ) from exc

    def _log(self, message: str, *args: object) -> None:
        if args:
            message = message % args
        print(f"[orchestrator] {message}")


def _load_devices(args: argparse.Namespace) -> List[DeviceTarget]:
    if args.devices_file:
        raw = Path(args.devices_file).read_text(encoding="utf-8")
        data = json.loads(raw)
        descriptors = _ensure_descriptors(data)
        return _build_devices_from_descriptors(descriptors, args.port_base)

    if args.serials:
        serial_descriptors: List[Descriptor] = []
        for entry in args.serials.split(","):
            serial_role = entry.strip().split(":")
            serial = serial_role[0]
            role = serial_role[1] if len(serial_role) > 1 else "slave"
            serial_descriptors.append({"serial": serial, "role": role})
        return _build_devices_from_descriptors(
            serial_descriptors,
            args.port_base,
        )

    output = subprocess.run(
        ["adb", "devices"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    discovered: List[Descriptor] = []
    for line in output.splitlines()[1:]:
        stripped = line.strip()
        if not stripped or "offline" in stripped or "unauthorized" in stripped:
            continue
        parts = stripped.split("\t")
        if len(parts) >= 2 and parts[1] == "device":
            discovered.append({"serial": parts[0]})
    if not discovered:
        raise OrchestratorError("adb reports no connected devices/emulators")
    for idx, descriptor in enumerate(discovered):
        descriptor.setdefault("role", "master" if idx == 0 else "slave")
    return _build_devices_from_descriptors(discovered, args.port_base)


def _ensure_descriptors(data: object) -> List[Descriptor]:
    if not isinstance(data, list):
        raise OrchestratorError("Devices file must be a list of objects")
    descriptors: List[Descriptor] = []
    entries = cast(List[Any], data)
    for entry in entries:
        if not isinstance(entry, Mapping):
            raise OrchestratorError("Device descriptor must be an object")
        entry_map = cast(Mapping[str, Any], entry)
        serial_value = entry_map.get("serial")
        if serial_value is None:
            raise OrchestratorError("Each descriptor requires a serial field")
        descriptor: Descriptor = {"serial": str(serial_value)}
        role_value = entry_map.get("role")
        if role_value is not None:
            descriptor["role"] = str(role_value)
        name_value = entry_map.get("name")
        if name_value is not None:
            descriptor["name"] = str(name_value)
        descriptors.append(descriptor)
    return descriptors


def _build_devices_from_descriptors(
    descriptors: List[Descriptor],
    port_base: int,
) -> List[DeviceTarget]:
    devices: List[DeviceTarget] = []
    for idx, descriptor in enumerate(descriptors):
        serial = descriptor["serial"]
        role = descriptor.get("role", "slave")
        name = descriptor.get("name", f"{role}-{idx}")
        devices.append(
            DeviceTarget(
                serial=serial,
                role=role,
                name=name,
                local_port=port_base + idx,
            )
        )
    return devices


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="HydraCam multi-device orchestrator",
    )
    parser.add_argument(
        "--devices-file",
        help="JSON file describing devices (serial/role)",
    )
    parser.add_argument(
        "--serials",
        help="Comma-separated serial[:role] list (first defaults to master)",
    )
    parser.add_argument(
        "--scenario",
        default="smoke",
        help="Scenario id to execute (default: smoke)",
    )
    parser.add_argument(
        "--port-base",
        type=int,
        default=DEFAULT_PORT_BASE,
        help="Starting localhost port used for adb forwarding",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Configure forwarding only (skip HTTP calls)",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Path to a manifest JSON file that drives multi-step scenarios",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("automation_runs"),
        help="Directory to store run artifacts",
    )
    # emulator control flags for experiments
    parser.add_argument(
        "--boot-emulators",
        type=int,
        default=0,
        help="Start N Android emulators for experiments",
    )
    parser.add_argument(
        "--avd-base",
        type=str,
        default="Pixel_7",
        help="Base AVD name to use when booting emulators",
    )
    parser.add_argument(
        "--emulator-start-port",
        type=int,
        default=5554,
        help="Starting port for first emulator (increments by 2)",
    )
    parser.add_argument(
        "--shutdown-emulators",
        type=int,
        default=0,
        help="Power down N running Android emulators",
    )
    parser.add_argument(
        "--kill-all-emulators",
        action="store_true",
        help="Kill all Android emulators and shutdown iOS simulators",
    )
    parser.add_argument(
        "--backend-base-url",
        help="HydraCam API base URL (overrides HYDRACAM_API_BASE)",
    )
    parser.add_argument(
        "--backend-token",
        help=("HydraCam automation API token " "(overrides HYDRACAM_AUTOMATION_TOKEN)"),
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    try:
        # handle emulator control commands first (short-circuit)
        if args.boot_emulators and args.boot_emulators > 0:
            manager = EmulatorManager()
            print(f"[orchestrator] Booting {args.boot_emulators} emulator(s)")
            manager.start_n_emulators(
                args.avd_base, args.boot_emulators, args.emulator_start_port
            )
            print("[orchestrator] Boot requests issued")
            return 0

        if args.shutdown_emulators and args.shutdown_emulators > 0:
            manager = EmulatorManager()
            android = manager.list_android_emulators()
            to_stop = android[: args.shutdown_emulators]
            for dev in to_stop:
                print(f"[orchestrator] Stopping {dev}")
                manager.stop_android_emulator(dev)
            print("[orchestrator] Stop requests issued")
            return 0

        if args.kill_all_emulators:
            manager = EmulatorManager()
            print("[orchestrator] Killing all emulators (android + ios)")
            manager.kill_all_emulators(force=False)
            ok = manager.verify_no_emulators()
            print(f"[orchestrator] verify_no_emulators -> {ok}")
            return 0

        devices = _load_devices(args)
        backend_base = args.backend_base_url or os.getenv("HYDRACAM_API_BASE")
        backend_token = args.backend_token or os.getenv(
            "HYDRACAM_AUTOMATION_TOKEN",
        )
        orchestrator = MultiDeviceOrchestrator(
            devices,
            dry_run=args.dry_run,
            manifest=args.manifest,
            scenario=args.scenario,
            output_root=args.output_dir,
            backend_base_url=backend_base,
            backend_token=backend_token,
        )
        orchestrator.run()
    except OrchestratorError as exc:
        print(f"[orchestrator] ERROR: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
