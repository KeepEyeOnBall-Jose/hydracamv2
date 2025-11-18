import os
import subprocess
import logging
import time
from typing import List


class EmulatorManager:
    def __init__(self, log_dir="logs"):
        self.log_dir = log_dir
        os.makedirs(self.log_dir, exist_ok=True)
        logging.basicConfig(level=logging.INFO)

    def start_emulator(self, avd_name, port, read_only: bool = False):
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

        logging.info(
            "Started emulator %s on port %s. Logs: %s", avd_name, port, log_file
        )
        return process

    def start_n_emulators(
        self,
        avd_name_base: str,
        n: int,
        start_port: int = 5554,
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
        procs = []
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

            port = start_port + i * 2
            proc = self.start_emulator(avd_name, port, read_only=read_only)
            procs.append(proc)

            # give emulator a small stagger to avoid ADB race conditions
            time.sleep(1.0)

            # Optionally wait until the emulator shows up in `adb devices`
            if wait_per_instance:
                device_id = f"emulator-{port}"
                deadline = time.time() + float(per_instance_timeout)
                while time.time() < deadline:
                    ids = self.list_android_emulators()
                    if device_id in ids:
                        logging.info("Emulator %s appeared in adb", device_id)
                        break
                    time.sleep(per_instance_interval)
                else:
                    logging.warning(
                        "Emulator %s did not appear in adb after %ds",
                        device_id,
                        per_instance_timeout,
                    )
        return procs

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
                ["xcrun", "simctl", "list", "booted"], encoding="utf-8"
            )
            ios_booted = bool(out.strip())
        except Exception:
            ios_booted = False

        if android_ids:
            logging.info("Still running Android emulators: %s", android_ids)
        if ios_booted:
            logging.info("iOS simulators still booted")

        return not android_ids and not ios_booted
