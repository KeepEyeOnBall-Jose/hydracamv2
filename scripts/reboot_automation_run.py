#!/usr/bin/env python3
"""Reboot the last-known HydraCam multi-device automation flow.

This wrapper keeps the existing building blocks (`emulator_manager.py`,
`multi_device_orchestrator.py`) but turns them into a single restart path:

1. Optionally build the Android automation APK.
2. Optionally boot the standard Hydra emulator cluster.
3. Install / relaunch HydraCam with master/slave intent extras.
4. Invoke the orchestrator manifest.
5. Optionally shut emulators back down.

It defaults to the most recent documented checkpoint in this repo: the
`quad_smoke_extended` manifest with one master and optional slave emulators.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

ORCHESTRATOR = REPO_ROOT / "scripts" / "multi_device_orchestrator.py"
DEFAULT_MANIFEST = REPO_ROOT / "automation_scenarios" / "quad_smoke_extended.json"
DEFAULT_APK_PATH = REPO_ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
PACKAGE_NAME = "com.amaia23.hydracam"
MAIN_ACTIVITY = f"{PACKAGE_NAME}/.MainActivity"
MASTER_BRIDGE_PORT = 4040
DEFAULT_EMULATOR_MASTER_IP = "10.0.2.2"
DEFAULT_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.ACCESS_MEDIA_LOCATION",
)
ADB_READY_TIMEOUT_SECONDS = 180
BOOT_COMPLETED_TIMEOUT_SECONDS = 240


@dataclass(frozen=True)
class DeviceLaunchTarget:
    serial: str
    role: str


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--serials",
        help=(
            "Comma-separated device serials. First becomes master, remaining devices "
            "become slaves. If omitted, connected adb devices are discovered."
        ),
    )
    parser.add_argument(
        "--boot-hydra-cluster",
        action="store_true",
        help="Boot Hydra_Master_API34 plus the standard Hydra slave AVDs before launching the app.",
    )
    parser.add_argument(
        "--cluster-size",
        type=int,
        default=3,
        help="How many Hydra cluster devices to use when --boot-hydra-cluster is set (default: 3).",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Manifest to pass to the multi-device orchestrator.",
    )
    parser.add_argument(
        "--scenario",
        help="Scenario name recorded in automation output (defaults to manifest stem).",
    )
    parser.add_argument(
        "--apk-path",
        type=Path,
        default=DEFAULT_APK_PATH,
        help="APK to install on Android devices.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip building the automation APK before launching devices.",
    )
    parser.add_argument(
        "--skip-install",
        action="store_true",
        help="Skip adb install and only relaunch the already-installed app.",
    )
    parser.add_argument(
        "--skip-grants",
        action="store_true",
        help="Skip runtime permission grants.",
    )
    parser.add_argument(
        "--preferred-master-ip",
        help=(
            "IP that slave devices should use to reach the master. Defaults to 10.0.2.2 "
            "for emulator-based runs."
        ),
    )
    parser.add_argument(
        "--master-port",
        type=int,
        default=MASTER_BRIDGE_PORT,
        help="Master WebSocket port to expose via adb forward for emulator slaves (default: 4040).",
    )
    parser.add_argument(
        "--stabilize-seconds",
        type=float,
        default=15.0,
        help="Seconds to wait after launching the app before invoking the orchestrator.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "automation_runs",
        help="Artifact directory passed through to the orchestrator.",
    )
    parser.add_argument(
        "--backend-base-url",
        help="Optional HydraCam API base URL for backend verification.",
    )
    parser.add_argument(
        "--backend-token",
        help="Optional HydraCam automation token for backend verification.",
    )
    parser.add_argument(
        "--shutdown-emulators",
        action="store_true",
        help="Shut down Android emulators and iOS simulators after the run finishes.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the reboot plan without executing adb / flutter / orchestrator commands.",
    )
    args = parser.parse_args(argv)
    if not args.scenario:
        args.scenario = args.manifest.stem
    return args


def log(message: str) -> None:
    print(f"[reboot] {message}")


def run_checked(
    cmd: Sequence[str],
    *,
    cwd: Path | None = None,
    dry_run: bool = False,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str] | None:
    joined = " ".join(cmd)
    log(joined)
    if dry_run:
        return None
    return subprocess.run(
        list(cmd),
        cwd=str(cwd) if cwd else None,
        check=True,
        text=True,
        capture_output=capture_output,
    )


def build_apk(args: argparse.Namespace) -> None:
    if args.skip_build:
        log("Skipping APK build")
        return
    run_checked(
        [
            "flutter",
            "build",
            "apk",
            "--debug",
            "--dart-define=HYDRACAM_AUTOMATION=true",
        ],
        cwd=REPO_ROOT,
        dry_run=args.dry_run,
    )
    if not args.dry_run and not args.apk_path.exists():
        raise FileNotFoundError(f"Expected APK not found at {args.apk_path}")


def discover_adb_devices(dry_run: bool = False) -> List[str]:
    if dry_run:
        return []
    completed = run_checked(["adb", "devices"], capture_output=True)
    assert completed is not None
    serials: List[str] = []
    for line in completed.stdout.splitlines()[1:]:
        stripped = line.strip()
        if not stripped or "offline" in stripped or "unauthorized" in stripped:
            continue
        parts = stripped.split()
        if len(parts) >= 2 and parts[1] == "device":
            serials.append(parts[0])
    return serials


def get_adb_state(serial: str) -> str:
    completed = subprocess.run(
        ["adb", "-s", serial, "get-state"],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def wait_for_adb_ready(serial: str, timeout_seconds: int = ADB_READY_TIMEOUT_SECONDS) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        state = get_adb_state(serial)
        if state == "device":
            log(f"adb ready: {serial}")
            return
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for adb-ready device: {serial}")


def read_shell_value(serial: str, command: list[str]) -> str:
    completed = subprocess.run(
        ["adb", "-s", serial, "shell", *command],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def wait_for_boot_completed(
    serial: str,
    timeout_seconds: int = BOOT_COMPLETED_TIMEOUT_SECONDS,
) -> None:
    wait_for_adb_ready(serial, timeout_seconds=min(timeout_seconds, ADB_READY_TIMEOUT_SECONDS))
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        boot_completed = read_shell_value(serial, ["getprop", "sys.boot_completed"])
        package_ready = read_shell_value(serial, ["getprop", "dev.bootcomplete"])
        if boot_completed == "1" or package_ready == "1":
            log(f"boot completed: {serial}")
            return
        time.sleep(3)
    raise TimeoutError(f"Timed out waiting for Android boot completion: {serial}")


def boot_cluster(args: argparse.Namespace) -> List[str]:
    from scripts.emulator_manager import EmulatorManager, hydra_cluster_specs

    specs = hydra_cluster_specs()
    selected = specs[: max(args.cluster_size, 1)]
    if args.dry_run:
        for spec in selected:
            log(
                "would boot %s on emulator-%s (shared-net-id=%s)"
                % (spec.avd_name, spec.port, spec.shared_net_id)
            )
        return [f"emulator-{spec.port}" for spec in selected]

    manager = EmulatorManager()
    manager.start_emulator_specs(selected)
    serials = [f"emulator-{spec.port}" for spec in selected]
    log("Boot requests issued; waiting briefly for adb stability")
    time.sleep(5)
    return serials


def resolve_devices(args: argparse.Namespace) -> List[DeviceLaunchTarget]:
    if args.boot_hydra_cluster:
        serials = boot_cluster(args)
    elif args.serials:
        serials = [part.strip() for part in args.serials.split(",") if part.strip()]
    else:
        serials = discover_adb_devices(dry_run=args.dry_run)

    if not serials:
        raise RuntimeError(
            "No devices resolved. Pass --serials or use --boot-hydra-cluster."
        )

    devices: List[DeviceLaunchTarget] = []
    for index, serial in enumerate(serials):
        devices.append(
            DeviceLaunchTarget(serial=serial, role="master" if index == 0 else "slave")
        )
    return devices


def should_use_emulator_master_alias(devices: Iterable[DeviceLaunchTarget]) -> bool:
    serials = [device.serial for device in devices]
    return bool(serials) and all(serial.startswith("emulator-") for serial in serials)


def grant_permissions(serial: str, dry_run: bool) -> None:
    for permission in DEFAULT_PERMISSIONS:
        try:
            run_checked(
                ["adb", "-s", serial, "shell", "pm", "grant", PACKAGE_NAME, permission],
                dry_run=dry_run,
            )
        except subprocess.CalledProcessError:
            log(f"permission grant skipped for {serial}: {permission}")


def prepare_master_forward(master_serial: str, port: int, dry_run: bool) -> None:
    if not dry_run:
        wait_for_boot_completed(master_serial)
    run_checked(
        ["adb", "-s", master_serial, "forward", f"tcp:{port}", f"tcp:{port}"],
        dry_run=dry_run,
    )


def launch_device(
    device: DeviceLaunchTarget,
    *,
    apk_path: Path,
    skip_install: bool,
    skip_grants: bool,
    preferred_master_ip: str | None,
    dry_run: bool,
) -> None:
    if not dry_run:
        wait_for_boot_completed(device.serial)

    if not skip_install:
        run_checked(["adb", "-s", device.serial, "install", "-r", str(apk_path)], dry_run=dry_run)

    if not skip_grants:
        grant_permissions(device.serial, dry_run=dry_run)

    run_checked(["adb", "-s", device.serial, "shell", "am", "force-stop", PACKAGE_NAME], dry_run=dry_run)

    launch_cmd = [
        "adb",
        "-s",
        device.serial,
        "shell",
        "am",
        "start",
        "-n",
        MAIN_ACTIVITY,
        "--es",
        "role",
        device.role,
    ]
    if device.role == "slave":
        launch_cmd.extend(["--ez", "forceSlaveMode", "true"])
        if preferred_master_ip:
            launch_cmd.extend(["--es", "preferredMasterIp", preferred_master_ip])
    run_checked(launch_cmd, dry_run=dry_run)


def build_serials_arg(devices: Iterable[DeviceLaunchTarget]) -> str:
    return ",".join(f"{device.serial}:{device.role}" for device in devices)


def run_orchestrator(
    args: argparse.Namespace,
    devices: List[DeviceLaunchTarget],
) -> None:
    command = [
        sys.executable,
        str(ORCHESTRATOR),
        "--serials",
        build_serials_arg(devices),
        "--manifest",
        str(args.manifest),
        "--scenario",
        args.scenario,
        "--output-dir",
        str(args.output_dir),
    ]
    if args.backend_base_url:
        command.extend(["--backend-base-url", args.backend_base_url])
    if args.backend_token:
        command.extend(["--backend-token", args.backend_token])
    run_checked(command, cwd=REPO_ROOT, dry_run=args.dry_run)


def shutdown_emulators(dry_run: bool) -> None:
    from scripts.emulator_manager import EmulatorManager

    if dry_run:
        log("would request shutdown of Android emulators and iOS simulators")
        return
    manager = EmulatorManager()
    manager.kill_all_emulators(force=False)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    devices = resolve_devices(args)
    master = devices[0]

    preferred_master_ip = args.preferred_master_ip
    if preferred_master_ip is None and should_use_emulator_master_alias(devices):
        preferred_master_ip = DEFAULT_EMULATOR_MASTER_IP

    build_apk(args)

    if preferred_master_ip == DEFAULT_EMULATOR_MASTER_IP:
        prepare_master_forward(master.serial, args.master_port, dry_run=args.dry_run)

    for device in devices:
        launch_device(
            device,
            apk_path=args.apk_path,
            skip_install=args.skip_install,
            skip_grants=args.skip_grants,
            preferred_master_ip=preferred_master_ip,
            dry_run=args.dry_run,
        )

    if args.stabilize_seconds > 0:
        if args.dry_run:
            log(f"would wait {args.stabilize_seconds:.1f}s for app startup")
        else:
            log(f"waiting {args.stabilize_seconds:.1f}s for app startup")
            time.sleep(args.stabilize_seconds)

    run_orchestrator(args, devices)

    if args.shutdown_emulators:
        shutdown_emulators(dry_run=args.dry_run)

    log("automation reboot flow complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
