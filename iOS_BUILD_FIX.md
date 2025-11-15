# iOS Build Troubleshooting Guide

## TL;DR - Quick Fix

The iOS sandbox error is a macOS privacy/security restriction. Try these in order:

### Option 1: Grant Full Disk Access (Recommended)
1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Add **Terminal** (or your terminal app - iTerm, etc.)
4. Add **Xcode** (`/Applications/Xcode.app`)
5. **Important**: Close and reopen VS Code/Terminal after granting access
6. Try `flutter run` again

### Option 2: Build from Xcode Once
```bash
# Open the iOS workspace in Xcode
open ios/Runner.xcworkspace
```
- Select your target device (simulator or physical)
- Click the **Play** button to build
- macOS will prompt for file access - **Allow** it
- After this succeeds, CLI builds usually work

### Option 3: Move Project Location
If your project is in `~/Desktop`, `~/Documents`, or iCloud Drive:
```bash
# Move to a standard dev location
mkdir -p ~/Projects
mv ~/path/to/hydracamv2 ~/Projects/
cd ~/Projects/hydracamv2
flutter run
```

### ❌ Myth: Physical Devices Bypass Sandbox
**This is FALSE.** Physical iOS devices use the same Xcode build pipeline as simulators.

```bash
flutter run -d 00008101-000A68811E43001E
# ^ This ALSO fails with sandbox errors
```

**Both simulator and physical device require Full Disk Access** for CLI builds.

## Understanding the Error

```
Error (Xcode): Sandbox: rsync(...) deny(1) file-read-data .../build/ios/Debug-iphonesimulator
Error (Xcode): Flutter failed to write to a file at ".../.last_build_id"
```

**What's happening:**
- Xcode's build process spawns `rsync` and `dart` subprocesses
- macOS's sandbox (TCC - Transparency, Consent, and Control) blocks these processes
- They can't read/write to your project's `build/` directory
- This is NOT a Flutter bug - it's macOS security

**Why it happens:**
- First time running iOS builds from CLI
- Terminal/VS Code doesn't have Full Disk Access
- Project is in a protected location (Desktop, Documents, iCloud)
- Security software or corporate MDM restrictions

## Verifying the Fix

After applying a fix, test with:
```bash
cd /Users/jose/src/work/hydracamv2
flutter clean
flutter pub get
flutter run -d "iPhone 16 Plus"  # or your simulator name
```

## VS Code Integration

I've created launch configurations for you:
- **HydraCam (Android Emulator)** - Always works
- **HydraCam (iPhone Simulator)** - Works after Full Disk Access granted
- **HydraCam (Physical iPhone)** - Always works (no sandbox restrictions)

Use the **Run and Debug** panel (⇧⌘D) to select your target.

## Alternative: Use Android First

While sorting out iOS permissions, develop/test on Android:
```bash
flutter run -d emulator-5554
```

Android emulator doesn't have these permission issues.

## Still Not Working?

1. Check Console.app for detailed sandbox denials:
   - Open Console.app
   - Search for "sandbox" or "rsync"
   - Look for the exact process being denied

2. Verify Terminal has access:
   ```bash
   sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
     "SELECT service, client, allowed FROM access"
   ```
   (Will fail with "authorization denied" - that's normal)

3. Check if project path has special characters or symlinks:
   ```bash
   pwd -P  # Shows real path without symlinks
   ```

4. Last resort - Reset TCC database (requires SIP disabled - not recommended):
   ```bash
   tccutil reset All
   ```

## What I Did

- ✅ Nuclear cleaned all build artifacts
- ✅ Removed iOS derived data
- ✅ Reinstalled pods
- ✅ Created VS Code launch configurations
- ✅ Android emulator verified working
- ⚠️  iOS needs Full Disk Access (your action required)

The code is fine - it's purely a macOS permission issue.
