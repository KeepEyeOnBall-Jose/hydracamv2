import os
import subprocess
import logging
import time
from dataclasses import dataclass
from typing import List


@dataclass(frozen=True)
class EmulatorLaunchSpec:
    avd_name: str
    port: int
    shared_net_id: int | None = None
    read_only: bool = False


HYDRA_CLUSTER_AVDS = (
    "Hydra_Master_API34",
    "Hydra_SlaveA_API34",
    "Hydra_SlaveB_API34",
    "Hydra_SlaveC_API34",
)


def hydra_cluster_specs(
    start_port: int = 5554,
    start_shared_net_id: int = 11,
) -> List[EmulatorLaunchSpec]:
    """Return launch specs for the standard Hydra 4-emulator cluster."""
    specs: List[EmulatorLaunchSpec] = []
    for index, avd_name in enumerate(HYDRA_CLUSTER_AVDS):
        specs.append(
            EmulatorLaunchSpec(
                avd_name=avd_name,
                port=start_port + index * 2,
                shared_net_id=start_shared_net_id + index,
            )
        )
    return specs


def parse_emulator_spec(spec_text: str) -> EmulatorLaunchSpec:
    """Parse AVD:PORT[:SHARED_NET_ID] into an EmulatorLaunchSpec."""
    parts = spec_text.split(":")
    if len(parts) not in (2, 3):
        raise ValueError(
            f"Invalid emulator spec '{spec_text}'. Expected AVD:PORT[:SHARED_NET_ID]."
        )

    avd_name = parts[0].strip()
    if not avd_name:
        raise ValueError("AVD name cannot be empty")

    try:
        port = int(parts[1])
    except ValueError as exc:
        raise ValueError(f"Invalid emulator port in '{spec_text}'") from exc

    shared_net_id = None
    if len(parts) == 3 and parts[2].strip():
        try:
            shared_net_id = int(parts[2])
        except ValueError as exc:
            raise ValueError(
                f"Invalid shared network id in '{spec_text}'"
            ) from exc

    return EmulatorLaunchSpec(
        avd_name=avd_name,
        port=port,
        shared_net_id=shared_net_id,
    )


class EmulatorManager:
    def __init__(self, log_dir="logs"):
        self.log_dir = log_dir
        os.makedirs(self.log_dir, exist_ok=True)
        logging.basicConfig(level=logging.INFO)

    def start_emulator(
        self,
        avd_name,
        port,
        read_only: bool = False,
        shared_net_id: int | None = None,
    ):
        """
        Starts an Android emulator with the specified AVD name and port.
        Logs output to a project-specific log file instead of /tmp.
        """
        log_file = os.path.join(self.log_dir, f"emulator_{port}.log")
        command = [
            "nohup",
            os.path.expanduser("~/Library/Android/sdk/emulator/emulator"),
            "-avd",
            avd_name,
            "-port",
            str(port),
            "-no-snapshot",
        ]

        if read_only:
            command.append("-read-only")

        if shared_net_id is not None:
            command += ["-shared-net-id", str(shared_net_id)]

        # continue with GPU selection
        command += [
            "-gpu",
            "swiftshader_indirect",
        ]

        # Redirect stdout and stderr to the log file
        with open(log_file, "w", encoding="utf-8") as logfile:
            process = subprocess.Popen(
                command, stdout=logfile, stderr=subprocess.STDOUT
            )

        if shared_net_id is None:
            logging.info(
                "Started emulator %s on port %s. Logs: %s",
                avd_name,
                port,
                log_file,
            )
        else:
            logging.info(
                "Started emulator %s on port %s with shared net id %s "
                "(secondary IP 10.1.2.%s). Logs: %s",
                avd_name,
                port,
                shared_net_id,
                shared_net_id,
                log_file,
            )
        return process

    def _wait_for_emulator(
        self,
        device_id: str,
        per_instance_timeout: int,
        per_instance_interval: float,
    ) -> None:
        deadline = time.time() + float(per_instance_timeout)
        while time.time() < deadline:
            ids = self.list_android_emulators()
            if device_id in ids:
                logging.info("Emulator %s appeared in adb", device_id)
                return
            time.sleep(per_instance_interval)

        logging.warning(
            "Emulator %s did not appear in adb after %ds",
            device_id,
            per_instance_timeout,
        )

    def build_n_emulator_specs(
        self,
        avd_name_base: str,
        n: int,
        start_port: int = 5554,
        shared_net_id_start: int | None = None,
    ) -> List[EmulatorLaunchSpec]:
        """Build N emulator launch specs from a shared base AVD name."""
        specs: List[EmulatorLaunchSpec] = []
        for i in range(n):
            # If caller provided a placeholder, use it (e.g. 'Pixel_7_{i}').
            # Otherwise reuse the same AVD name for each instance which is
            # valid for launching multiple emulator processes of the same AVD.
            if "{i}" in avd_name_base:
                avd_name = avd_name_base.format(i=i)
                read_only = False
            else:
                avd_name = avd_name_base
                # If launching multiple instances from the same AVD, enable
                # -read-only to allow concurrent runs.
                read_only = n > 1
                if read_only:
                    logging.info(
                        "Starting multiple read-only instances using AVD %s",
                        avd_name,
                    )

            shared_net_id = None
            if shared_net_id_start is not None:
                shared_net_id = shared_net_id_start + i

            specs.append(
                EmulatorLaunchSpec(
                    avd_name=avd_name,
                    port=start_port + i * 2,
                    shared_net_id=shared_net_id,
                    read_only=read_only,
                )
            )
        return specs

    def start_emulator_specs(
        self,
        specs: List[EmulatorLaunchSpec],
        wait_per_instance: bool = True,
        per_instance_timeout: int = 90,
        per_instance_interval: float = 2.0,
    ) -> List[subprocess.Popen]:
        """Start emulators from explicit launch specs."""
        procs: List[subprocess.Popen] = []
        for spec in specs:
            proc = self.start_emulator(
                spec.avd_name,
                spec.port,
                read_only=spec.read_only,
                shared_net_id=spec.shared_net_id,
            )
            procs.append(proc)

            # give emulator a small stagger to avoid ADB race conditions
            time.sleep(1.0)

            if wait_per_instance:
                self._wait_for_emulator(
                    f"emulator-{spec.port}",
                    per_instance_timeout,
                    per_instance_interval,
                )
        return procs

    def start_n_emulators(
        self,
        avd_name_base: str,
        n: int,
        start_port: int = 5554,
        shared_net_id_start: int | None = None,
        wait_per_instance: bool = True,
        per_instance_timeout: int = 90,
        per_instance_interval: float = 2.0,
    ) -> List[subprocess.Popen]:
        """
        Start `n` emulators using `avd_name_base` as the base AVD name.
        AVD names will be constructed as `{avd_name_base}_{i}` if `n>1`.
        Ports will increment by 2 (emulator uses even/odd pair scheme).
        Returns list of Popen objects for the started processes.
        """
        specs = self.build_n_emulator_specs(
            avd_name_base,
            n,
            start_port=start_port,
            shared_net_id_start=shared_net_id_start,
        )
        return self.start_emulator_specs(
            specs,
            wait_per_instance=wait_per_instance,
            per_instance_timeout=per_instance_timeout,
            per_instance_interval=per_instance_interval,
        )

    def list_android_emulators(self) -> List[str]:
        """Return list of Android emulator device ids (e.g. emulator-5554)."""
        try:
            out = subprocess.check_output(["adb", "devices"], encoding="utf-8")
        except Exception:
            return []
        ids = []
        for line in out.splitlines():
            if line.startswith("emulator-"):
                parts = line.split()
                if parts:
                    ids.append(parts[0])
        return ids

    def stop_android_emulator(self, device_id: str) -> None:
        """Gracefully stop a single Android emulator by sending `emu kill`."""
        try:
            subprocess.run(["adb", "-s", device_id, "emu", "kill"], check=True)
            logging.info("Requested shutdown for %s", device_id)
        except subprocess.CalledProcessError:
            logging.warning("Failed to request shutdown for %s", device_id)

    def kill_all_emulators(self, force: bool = False) -> None:
        """
        Attempt to gracefully stop all Android emulators and shutdown iOS simulators.
        If `force` is True, will attempt to kill emulator processes as a last resort.
        """
        # Android emulators
        android_ids = self.list_android_emulators()
        for aid in android_ids:
            self.stop_android_emulator(aid)

        # iOS simulators
        try:
            subprocess.run(["xcrun", "simctl", "shutdown", "all"], check=False)
            logging.info("Requested shutdown of all iOS simulators")
        except Exception:
            logging.warning("Failed to request iOS simulator shutdown")

        if force:
            # best-effort kill of emulator processes
            try:
                subprocess.run(["pkill", "-f", "emulator"], check=False)
                logging.info("Ran pkill -f emulator")
            except Exception:
                pass

    def verify_no_emulators(self, wait_seconds: int = 3) -> bool:
        """
        Verify there are no running Android emulators or booted iOS simulators.
        Returns True when none are running, False otherwise.
        """
        time.sleep(wait_seconds)
        android_ids = self.list_android_emulators()
        ios_booted = False
        try:
            out = subprocess.check_output(
                ["xcrun", "simctl", "list", "devices", "booted"],
                encoding="utf-8",
            )
            ios_booted = "(Booted)" in out
        except Exception:
            ios_booted = False

        if android_ids:
            logging.info("Still running Android emulators: %s", android_ids)
        if ios_booted:
            logging.info("iOS simulators still booted")

        return not android_ids and not ios_booted
