#!/usr/bin/env python3
"""Small helper to stop all emulators (Android + iOS) and verify none are left."""

# Make the project root importable so callers can run this script directly
# without setting PYTHONPATH externally.
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from scripts.emulator_manager import EmulatorManager


def main() -> int:
    manager = EmulatorManager()
    print("[stopper] Requesting graceful shutdown of all emulators (android + ios)")
    manager.kill_all_emulators(force=False)
    ok = manager.verify_no_emulators(wait_seconds=5)
    if ok:
        print("[stopper] No emulators or simulators appear to be running")
        return 0
    else:
        print("[stopper] Some emulators/simulators are still running")
        android = manager.list_android_emulators()
        if android:
            print(f"[stopper] Android still: {android}")
        else:
            print("[stopper] No Android emulators running")
        # we don't try to parse simctl output here — simctl list booted returns
        # non-empty when iOS simulators are booted; manager.verify_no_emulators
        # already logged that.
        return 1


if __name__ == "__main__":
    sys.exit(main())
