"""Shared helpers for the HydraCam Android probing scripts.

Import submodules directly, for example::

    from hydracam_lib.proc import CommandResult, run, checked_run
    from hydracam_lib.adb import DEFAULT_ADB, AndroidDevice, list_devices

The package is intentionally import-side-effect free; nothing is re-exported
here so that importing one submodule never drags the other in.
"""
