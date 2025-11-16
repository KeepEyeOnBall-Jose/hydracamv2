#!/usr/bin/env python3
"""HydraCam multi-device orchestration entrypoint."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, cast
from urllib.parse import urlparse

AUTOMATION_REMOTE_PORT = 4762
DEFAULT_PORT_BASE = 5900


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
        if scenario == "smoke":
            return self._run_smoke_scenario()
        raise OrchestratorError(f"Unknown scenario '{self.scenario}'")

    def _run_smoke_scenario(self) -> Dict[str, Any]:
        master = self._get_master()
        if master is None:
            raise OrchestratorError(
                "Smoke scenario requires at least one master device",
            )

        payload: Dict[str, object] = {"sessionId": f"automation-{int(time.time())}"}
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
        devices_path = self.run_dir / "devices.json"
        devices_path.write_text(
            json.dumps(self.summary_stub["devices"], indent=2),
            encoding="utf-8",
        )
        self._log("Artifacts will be stored under %s", self.run_dir)

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
                        url_candidate = entry_map.get("downloadUrl") or entry_map.get(
                            "url"
                        )
                        if isinstance(url_candidate, str) and url_candidate:
                            assets.append({"url": url_candidate})
        # Some APIs might flatten into `uploads` object keyed by guid
        uploads = payload.get("uploads")
        if isinstance(uploads, Mapping):
            uploads_map = cast(Mapping[str, Any], uploads)
            for entry in uploads_map.values():
                if isinstance(entry, Mapping):
                    entry_map = cast(Mapping[str, Any], entry)
                    url_candidate = entry_map.get("downloadUrl") or entry_map.get("url")
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

    def _request(
        self,
        device: DeviceTarget,
        path: str,
        *,
        method: str,
        payload: Optional[Mapping[str, object]] = None,
    ) -> Dict[str, object]:
        url = self._build_url(device, path)
        data = None
        headers = {"Content-Type": "application/json"}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                body = response.read().decode("utf-8")
        except urllib.error.URLError as exc:  # pragma: no cover
            raise OrchestratorError(
                f"HTTP {method} {url} failed: {exc}",
            ) from exc
        return json.loads(body) if body else {}

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
        help="Optional scenario manifest (reserved for future phases)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("automation_runs"),
        help="Directory to store run artifacts",
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
