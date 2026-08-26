#!/usr/bin/env python3
"""
Check device status by querying the /session endpoint on all three emulators.
"""

import requests
import json

DEVICES = [
    ("Master (5554)", "http://127.0.0.1:5900/session"),
    ("Slave A (5556)", "http://127.0.0.1:5901/session"),
    ("Slave B (5558)", "http://127.0.0.1:5902/session"),
]


def main():
    print("=== Checking Device Types ===\n")

    for name, url in DEVICES:
        try:
            response = requests.get(url, timeout=5)
            response.raise_for_status()
            data = response.json()

            print(f"{name}:")
            print(f"  Device Type: {data.get('deviceType', 'Unknown')}")
            print(f"  Queue Length: {data.get('queueLength', 0)}")
            print(f"  Is Uploading: {data.get('isUploading', False)}")
            print()

        except requests.exceptions.RequestException as e:
            print(f"{name}: ERROR - {e}\n")
        except json.JSONDecodeError as e:
            print(f"{name}: ERROR - Invalid JSON: {e}\n")


if __name__ == "__main__":
    main()
