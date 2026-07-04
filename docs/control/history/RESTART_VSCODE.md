# Full Disk Access - CRITICAL STEPS

## ✅ What You've Done
- Added Warp to Full Disk Access
- Added Terminal.app to Full Disk Access

## ❌ What's Missing
**VS Code is launching the Flutter/Xcode processes**, not Warp or Terminal directly.

## 🔧 Required Actions

### Step 1: Add VS Code to Full Disk Access
1. **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to **Applications**
4. Find and select **Visual Studio Code.app**
5. Click **Open**
6. ✅ Verify it appears in the list with checkbox enabled

### Step 2: QUIT Everything (Critical!)
The permission only applies to NEW processes, not running ones:

```bash
# Quit VS Code completely
# Press Cmd+Q in VS Code (or quit from menu)

# If using Warp terminal separately:
# Press Cmd+Q in Warp

# If processes still running, force quit:
killall "Visual Studio Code"
killall Warp
```

### Step 3: Reopen and Test
1. **Wait 5 seconds** (let macOS register the change)
2. Open **Visual Studio Code**
3. Open terminal in VS Code (`` Ctrl+` ``)
4. Run test:
   ```bash
   cd /Users/jose/src/work/hydracamv2
   flutter build ios --simulator --debug
   ```

## 📊 Verification

If successful, you'll see:
```
Building com.keepeyeonball for simulator (ios)...
Running Xcode build...
Xcode build done. ✓
```

If still failing with sandbox errors:
- Go back to System Settings
- Verify **Visual Studio Code** is in Full Disk Access list
- Try adding `/usr/bin/xcodebuild` if VS Code doesn't work

## 🎯 Quick Test Commands

After reopening VS Code:

```bash
# Test 1: Verify file access
ls -la /Users/jose/src/work/hydracamv2/build/ios/

# Test 2: iOS Simulator build
flutter build ios --simulator --debug

# Test 3: Run on simulator
flutter run -d 5CF4A12E-A8B5-4285-AE86-407B9067CB5F

# Test 4: Physical iPhone
flutter run -d 00008101-000A68811E43001E

# Test 5: Integration tests
flutter test integration_test/platform_test.dart -d 5CF4A12E-A8B5-4285-AE86-407B9067CB5F
```

## 🔍 Troubleshooting

### Still Getting Sandbox Errors?
Try this nuclear option:

```bash
# 1. Quit VS Code completely (Cmd+Q)

# 2. Open from command line with Full Disk Access inheritance
open -a "Visual Studio Code" --args --disable-extensions

# 3. Or try from Xcode directly:
open ios/Runner.xcworkspace
# Select device and click Run
```

### Check What Process Is Actually Blocked
```bash
# Run this in a separate terminal WHILE build is failing:
log stream --predicate 'eventMessage CONTAINS "Sandbox"' --level debug
```

This will show exactly which process is being denied.

---

## Next: I'll Wait for You to Restart VS Code

**Action Required:**
1. Quit VS Code (`Cmd+Q`)
2. Wait 5 seconds
3. Reopen VS Code
4. Let me know when ready, and I'll run the iOS builds
