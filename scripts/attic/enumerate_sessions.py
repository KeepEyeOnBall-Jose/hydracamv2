#!/usr/bin/env python3
"""
Enumerate session directories on Android devices and extract metadata.
"""

import subprocess
import json
import sys
import os


def run_adb(serial, *args):
    """Run an adb command for a specific device."""
    cmd = ["adb", "-s", serial] + list(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running {' '.join(cmd)}: {e.stderr}", file=sys.stderr)
        return None


def list_sessions(serial):
    """List session directories on a device."""
    app_data_dir = "/data/data/com.amaia23.hydracam/app_flutter"
    sessions_dir = f"{app_data_dir}/sessions"

    output = run_adb(
        serial,
        "shell",
        f"run-as com.amaia23.hydracam ls {sessions_dir} 2>/dev/null || echo ''",
    )
    if not output:
        return []

    return [line.strip() for line in output.split("\n") if line.strip()]


def get_session_metadata(serial, session_id):
    """Get metadata for a specific session."""
    app_data_dir = "/data/data/com.amaia23.hydracam/app_flutter"
    metadata_path = f"{app_data_dir}/sessions/{session_id}/metadata.json"

    output = run_adb(
        serial,
        "shell",
        f"run-as com.amaia23.hydracam cat {metadata_path} 2>/dev/null || echo '{{}}'",
    )
    if not output:
        return {}

    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return {}


def list_session_files(serial, session_id):
    """List all files in a session directory."""
    app_data_dir = "/data/data/com.amaia23.hydracam/app_flutter"
    session_dir = f"{app_data_dir}/sessions/{session_id}"

    output = run_adb(
        serial,
        "shell",
        f"run-as com.amaia23.hydracam ls -la {session_dir} 2>/dev/null || echo ''",
    )
    return output


def pull_session_file(serial, session_id, filename, local_dir):
    """Pull a file from a session directory."""
    app_data_dir = "/data/data/com.amaia23.hydracam/app_flutter"
    remote_path = f"{app_data_dir}/sessions/{session_id}/{filename}"
    local_path = os.path.join(local_dir, filename)

    # First copy to /sdcard (readable by adb)
    temp_path = f"/sdcard/Download/{filename}"
    run_adb(
        serial, "shell", f"run-as com.amaia23.hydracam cp {remote_path} {temp_path}"
    )

    # Then pull from /sdcard
    result = subprocess.run(
        ["adb", "-s", serial, "pull", temp_path, local_path],
        capture_output=True,
        text=True,
    )

    # Clean up temp file
    run_adb(serial, "shell", f"rm {temp_path}")

    return local_path if result.returncode == 0 else None


def main():
    devices = [
        ("emulator-5554", "Master"),
        ("emulator-5556", "Slave A"),
        ("emulator-5558", "Slave B"),
    ]

    print("=== Enumerating Session Directories ===\n")

    for serial, name in devices:
        print(f"{name} ({serial}):")

        sessions = list_sessions(serial)
        if not sessions:
            print("  No sessions found\n")
            continue

        print(f"  Found {len(sessions)} session(s):")
        for session_id in sessions:
            print(f"\n  Session: {session_id}")

            # Get metadata
            metadata = get_session_metadata(serial, session_id)
            if metadata:
                print(f"    Metadata: {json.dumps(metadata, indent=6)}")

            # List files
            files_output = list_session_files(serial, session_id)
            if files_output:
                print(f"    Files:")
                for line in files_output.split("\n"):
                    if line.strip():
                        print(f"      {line}")

        print()


if __name__ == "__main__":
    main()
