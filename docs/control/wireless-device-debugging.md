# Wireless Device Debugging

Use this runbook to prepare HydraCam phones for cable-free debugging. Keep all
devices and this Mac on the same trusted WiFi or hotspot network before starting.

## Android First-Time Setup

Do this once per Android phone:

1. Charge the phone and give it a physical label, for example
   `HydraCam-S10e-01`.
2. Join the same WiFi or hotspot network as the Mac.
3. Enable Developer options:
   - Settings > About phone > tap Build number seven times.
   - Settings > Developer options > enable `USB debugging`.
   - Enable `Stay awake` while charging for long test sessions.
4. Connect the phone by USB and accept the RSA debugging prompt.
5. From this repo, run:

```bash
python3 scripts/android_wireless_debug.py
```

For one specific phone:

```bash
python3 scripts/android_wireless_debug.py --serial <usb-serial>
```

The script prints the wireless target as `<phone-ip>:5555`. Use that target for
Flutter:

```bash
flutter devices
flutter run -d <phone-ip>:5555
```

After setup, unplug USB and verify the phone remains visible:

```bash
adb devices -l
flutter devices
```

## Android Daily Use

If the phone has not rebooted and its WiFi IP has not changed, reconnect with:

```bash
adb connect <phone-ip>:5555
flutter run -d <phone-ip>:5555
```

If the phone rebooted or changed network, connect by USB once and rerun:

```bash
python3 scripts/android_wireless_debug.py --serial <usb-serial>
```

To close the wireless ADB endpoint:

```bash
adb -s <phone-ip>:5555 usb
adb disconnect <phone-ip>:5555
```

Only leave `:5555` debugging enabled on trusted lab networks.

## Samsung Galaxy S10e

Prepare the S10e as the first repeatable inventory test:

1. Label it `HydraCam-S10e-01`.
2. Update Android as far as the phone allows, then reboot.
3. Join the same lab WiFi or HydraCam hotspot as the Mac.
4. Enable Developer options, `USB debugging`, and `Stay awake`.
5. Disable battery optimization for HydraCam after the app is installed.
6. Connect USB once, accept the RSA prompt, then run:

```bash
adb devices -l
python3 scripts/android_wireless_debug.py
flutter devices
```

Record the model, Android version, USB serial, WiFi IP, and final
`<ip>:5555` target in the active test notes or issue before assigning it a
master/slave role.

## Remaining Android Inventory

Process phones one at a time so labels and serials do not get mixed:

| Field | Example |
| --- | --- |
| Label | `HydraCam-Android-02` |
| Model | `Samsung Galaxy S10e` |
| OS | `Android 12` |
| USB serial | `R58...` |
| WiFi IP | `192.168.178.x` |
| Flutter target | `192.168.178.x:5555` |
| Default role | `master`, `slave`, or `reserve` |

For multi-phone test runs, prefer a stable router/hotspot with client isolation
disabled. HydraCam master/slave discovery and ADB both need device-to-device LAN
reachability.

## iPhone Wireless Debugging

iOS wireless debugging is controlled by Xcode/CoreDevice rather than ADB.

Do this once per iPhone:

1. Enable Developer Mode on the iPhone and reboot when prompted.
2. Join the same WiFi or hotspot network as the Mac.
3. Connect USB and trust this Mac.
4. Open Xcode > Window > Devices and Simulators.
5. Select the iPhone and enable `Connect via network`.
6. Keep the phone unlocked until Xcode finishes preparing it.
7. Unplug USB and verify:

```bash
xcrun devicectl list devices
flutter devices
flutter run -d <ios-udid>
```

If `devicectl` sees the iPhone but debugging cannot start, reopen Xcode's
Devices and Simulators window and let it finish mounting developer support. For
HydraCam, keep the existing physical-iOS white-screen blocker separate from
wireless pairing: a paired iPhone can still expose app-startup failures.
