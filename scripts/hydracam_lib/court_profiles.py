"""Per-model court phone hardware profiles for Samsung fleet enrollment.

Each profile defines the physical button combinations, firmware targets,
recovery/boot images, Heimdall flashing behavior, charge-cap mechanism, and
Wi-Fi provisioning mode. ``tested=True`` means the procedure was proven on
real hardware (Galaxy S10e / SM-G970F). Untested profiles require
``--allow-untested``.
"""

from __future__ import annotations

from typing import Any, Sequence

RECOVERY_IMAGES_S10E: list[dict[str, Any]] = [
    {
        "partition": "RECOVERY",
        "file": "recovery-magisk-v2.img",
        "sha1": "079c2caa7d5fe126f92f61908f640fc95047eb91",
        "bytes": 67633152,
    },
    {
        # Must be non-stock: on a normal boot /vendor/bin/install-recovery.sh
        # restores stock recovery when the boot image matches its patch source.
        "partition": "BOOT",
        "file": "boot-magisk-sar.img",
        "sha1": "f0ab867944223e147b8caab807d16935b5d2ee10",
        "bytes": 57671680,
    },
]

PROFILES: dict[str, dict[str, Any]] = {
    "SM-G970F": {
        "label": "S10e",
        "codename": "beyond0",
        "chipset": "Exynos 9820",
        "tested": True,
        "firmware": ["G970FXXSGHWC2", "G970FXXSGHWC1"],
        "root_method": "magisk-recovery",
        "bootloader_unlock": "blue-screen",
        "buttons": {
            "download": {
                "keys": ["Volume Down", "Bixby"],
                "usb": "plug-while-holding",
                "release_on": "the BLUE warning screen",
            },
            "unlock_confirm": [
                'LONG-press Volume Up (about 3 s) for "Device unlock mode"',
                "press Volume Up once more to confirm",
            ],
            "download_continue": (
                "press Volume Up SHORTLY (a long press offers to relock: never do that)"
            ),
            "exit_download": {
                "keys": ["Volume Down", "Power"],
                "hold_seconds": 7,
                "until": "the screen goes black",
            },
            "recovery_menu": {
                "keys": ["Volume Up", "Bixby", "Power"],
                "release_first": "Power",
                "release_first_on": 'the Samsung logo or the "bootloader unlocked" warning',
                "keep_holding": ["Volume Up", "Bixby"],
                "until": "the blue-on-black recovery menu",
            },
            "root_boot": {
                "keys": ["Volume Up", "Bixby", "Power"],
                "release_all_on": 'the "bootloader unlocked" warning screen',
            },
        },
        "images": RECOVERY_IMAGES_S10E,
        "heimdall_sessions": "single",
        "rooted_boot": "recovery",
        "reboot_command": 'su -c "reboot recovery"',
        "charge_cap": "kernel",
        "wifi": "cmd-wifi",
        "dnd_sticks": True,
    },
    "SM-G960F": {
        "label": "S9",
        "codename": "starlte",
        "chipset": "Exynos 9810",
        "tested": False,
        "firmware": [],
        "root_method": "twrp",
        "bootloader_unlock": "oem-toggle-only",
        "buttons": {
            "download": {
                "keys": ["Volume Down", "Bixby", "Power"],
                "usb": "plugged",
                "release_on": "the blue warning screen",
            },
            "download_continue": "press Volume Up shortly",
            "exit_download": {
                "keys": ["Volume Down", "Power"],
                "hold_seconds": 7,
                "until": "the screen goes black",
            },
            "recovery_menu": {
                "keys": ["Volume Up", "Bixby", "Power"],
                "release_first": "Power",
                "release_first_on": "the Samsung logo",
                "keep_holding": ["Volume Up", "Bixby"],
                "until": "TWRP",
            },
        },
        "images": [{"partition": "RECOVERY", "file": "twrp-starlte.img"}],
        "magisk_zip": "Magisk.apk",
        "heimdall_sessions": "single",
        "rooted_boot": "normal",
        "reboot_command": "reboot",
        "charge_cap": "slate-daemon",
        "wifi": "human",
        "dnd_sticks": False,
        "notes": "Android 10: no cmd wifi, add Wi-Fi by hand.",
    },
    "SM-G935F": {
        "label": "S7 edge",
        "codename": "hero2lte",
        "chipset": "Exynos 8890",
        "tested": False,
        "firmware": [],
        "root_method": "twrp",
        "bootloader_unlock": "oem-toggle-only",
        "buttons": {
            "download": {
                "keys": ["Home", "Volume Down", "Power"],
                "usb": "plugged",
                "release_on": "the blue warning screen",
            },
            "download_continue": "press Volume Up shortly",
            "exit_download": {
                "keys": ["Home", "Volume Down", "Power"],
                "hold_seconds": 7,
                "until": "the screen goes black",
            },
            "recovery_menu": {
                "keys": ["Home", "Volume Up", "Power"],
                "release_first": "Power",
                "release_first_on": "the Samsung logo",
                "keep_holding": ["Home", "Volume Up"],
                "until": "TWRP",
            },
        },
        "images": [{"partition": "RECOVERY", "file": "twrp-hero2lte.img"}],
        "magisk_zip": "Magisk.apk",
        "heimdall_sessions": "single",
        "rooted_boot": "normal",
        "reboot_command": "reboot",
        "charge_cap": "slate-daemon",
        "wifi": "human",
        "dnd_sticks": False,
        "notes": "Never set a screen lock before root: encrypted data fails verification.",
    },
    "SM-G780G": {
        "label": "S20 FE",
        "codename": "r8q",
        "chipset": "Snapdragon 865",
        "tested": False,
        "firmware": [],
        "root_method": "magisk-boot",
        "bootloader_unlock": "blue-screen",
        "buttons": {
            "download": {
                "keys": ["Volume Up", "Volume Down"],
                "usb": "plug-while-holding",
                "release_on": "the BLUE warning screen",
            },
            "unlock_confirm": [
                'LONG-press Volume Up (about 3 s) for "Device unlock mode"',
                "press Volume Up once more to confirm",
            ],
            "download_continue": (
                "press Volume Up SHORTLY (a long press offers to relock: never do that)"
            ),
            "exit_download": {
                "keys": ["Volume Down", "Power"],
                "hold_seconds": 7,
                "until": "the screen goes black",
            },
            "recovery_menu": {
                "keys": ["Volume Up", "Power"],
                "release_first": "Power",
                "release_first_on": "the Samsung logo",
                "keep_holding": ["Volume Up"],
                "until": "the recovery menu (USB cable must stay plugged in)",
            },
        },
        "images": [
            {"partition": "VBMETA", "file": "vbmeta-disabled-G780G.img"},
            {"partition": "BOOT", "file": "boot-magisk-G780G.img"},
        ],
        "heimdall_sessions": "single",
        "rooted_boot": "normal",
        "reboot_command": "reboot",
        "charge_cap": "kernel",
        "wifi": "cmd-wifi",
        "dnd_sticks": True,
        "notes": "Magisk-patched boot + vbmeta with verification disabled.",
    },
    "SM-G781B": {
        "label": "S20 FE 5G",
        "codename": "r8q",
        "chipset": "Snapdragon 865",
        "tested": False,
        "firmware": [],
        "root_method": "magisk-boot",
        "bootloader_unlock": "blue-screen",
        "buttons": {
            "download": {
                "keys": ["Volume Up", "Volume Down"],
                "usb": "plug-while-holding",
                "release_on": "the BLUE warning screen",
            },
            "unlock_confirm": [
                'LONG-press Volume Up (about 3 s) for "Device unlock mode"',
                "press Volume Up once more to confirm",
            ],
            "download_continue": (
                "press Volume Up SHORTLY (a long press offers to relock: never do that)"
            ),
            "exit_download": {
                "keys": ["Volume Down", "Power"],
                "hold_seconds": 7,
                "until": "the screen goes black",
            },
            "recovery_menu": {
                "keys": ["Volume Up", "Power"],
                "release_first": "Power",
                "release_first_on": "the Samsung logo",
                "keep_holding": ["Volume Up"],
                "until": "the recovery menu (USB cable must stay plugged in)",
            },
        },
        "images": [
            {"partition": "VBMETA", "file": "vbmeta-disabled-G781B.img"},
            {"partition": "BOOT", "file": "boot-magisk-G781B.img"},
        ],
        # Observed 2026-11-02: only ONE partition commits per heimdall session.
        "heimdall_sessions": "per-partition",
        "rooted_boot": "normal",
        "reboot_command": "reboot",
        "charge_cap": "kernel",
        "wifi": "cmd-wifi",
        "dnd_sticks": True,
        "notes": "As SM-G780G, but flash one partition per heimdall session.",
    },
}


def profile_for(model: str) -> dict[str, Any]:
    """Return a copy of the profile for ``model`` or raise ValueError."""
    profile = PROFILES.get(model)
    if profile is None:
        known = ", ".join(PROFILES.keys())
        raise ValueError(f"no profile for model {model}; known: {known}")
    return {"model": model, **profile}


def keys_text(keys: Sequence[str]) -> str:
    """Format a button list as a readable combo string."""
    return " + ".join(keys)
