# Video Upload Failure Analysis

## Date: November 20, 2025
## Session: 517d17d5-1293-4276-bafd-135b1fed4749

## Problem

**Videos were NOT uploaded to the backend**, despite the test orchestrator calling `start_recording` and `stop_recording` commands.

### Portal Evidence
- **Photos Uploaded:** ✅ 2 photos (from 2 devices)
- **Videos Uploaded:** ❌ 0 videos (table empty)
- Portal URL: https://hydracam.azurewebsites.net/HydraCam/Details/456

### Local Device Evidence
- **Photos on device:** 1 file
- **Videos on device:** 0 files
- **Metadata videos array:** Empty `[]`

## Root Cause Analysis

### Timeline of Events

| Time | Event | Source |
|------|-------|--------|
| 22:26:07 | `start_recording` automation command received | Orchestrator |
| 22:26:07 | Command scheduled for 22:26:10 (3s timer) | master_screen.dart |
| 22:26:10 | Scheduled time reached, start execution | master_screen.dart |
| 22:26:13 | `stop_recording` automation command received | Orchestrator |
| 22:26:13 | Command scheduled for 22:26:16 (3s timer) | master_screen.dart |
| 22:26:35 | **Video recording ACTUALLY starts** | camera_service.dart |
| 22:26:36 | "startRecordingVideo command finished" | Log |
| 22:26:54 | Session ended | Orchestrator |

### The Bug

**Problem:** The video recording initialization takes ~25 seconds from command to actual recording start, but the `stop_recording` command was sent only 6 seconds after `start_recording`.

**Timeline Math:**
- `start_recording` received: 22:26:07
- Timer delay: 3s → scheduled for 22:26:10
- Execution starts: 22:26:10
- Camera initialization time: ~25s
- **Recording actually starts:** 22:26:35

- `stop_recording` received: 22:26:13 (only 6s after start command!)
- Timer delay: 3s → scheduled for 22:26:16
- When stop executes at 22:26:16, **recording hasn't started yet**
- `_ensureRecordingState(shouldRecord: false)` checks `isRecording` → still `false`
- Returns early without doing anything!

### Code Flow Bug

```dart
Future<void> _ensureRecordingState({required bool shouldRecord}) async {
  if (shouldRecord == isRecording) {
    return;  // ❌ EARLY RETURN - no state change needed
  }
  await _toggleRecording(showCountdown: false, suppressSnackbars: true);
}
```

When `stop_recording` is called while the camera is still initializing:
1. `shouldRecord = false` (want to stop)
2. `isRecording = false` (not started yet)
3. `shouldRecord == isRecording` ✅ true
4. **Returns early without calling `_toggleRecording`!**

### Why the Video Never Saved

The recording started at 22:26:35 and continued running until the session ended at 22:26:54 (19 seconds of recording). 

When `end_session` was called, the recording was forcibly terminated **without properly saving the video file**:
- No "Video saved to session path" log entry
- No video file created in session directory
- No video added to metadata.json
- No video added to upload queue

## Secondary Issues

### 1. Long Camera Initialization Time
Camera took 25 seconds to initialize after command:
- 22:26:10: "Initializing camera..."
- 22:26:22: "Camera successfully initialized"
- 22:26:35: "Video recording started"

This 25-second delay is **much longer than the orchestrator expected**.

### 2. No Async State Protection
The automation commands don't protect against:
- Commands sent while previous command still executing
- State transitions that take significant time
- Camera initialization delays

### 3. Session End During Recording
When `end_session` is called while recording is active, the video is **discarded** rather than saved.

## Test Scenario Issue

The orchestrator scenario (`quad_smoke_extended.json`) has timing assumptions that don't match reality:

```json
{
  "name": "start-recording",
  "action": "command",
  "command": "start_recording"
},
{
  "name": "sleep-while-recording",
  "action": "sleep",
  "duration": 6.0  // ❌ Only 6 seconds
},
{
  "name": "stop-recording",
  "action": "command",
  "command": "stop_recording"
}
```

**Assumption:** Camera starts recording immediately  
**Reality:** Camera takes ~25 seconds to initialize and start

## Recommended Fixes

### Fix 1: Add Async State Tracking (HIGH PRIORITY)

```dart
bool _isRecordingTransitioning = false;

Future<void> _ensureRecordingState({required bool shouldRecord}) async {
  // Wait for any ongoing transitions
  while (_isRecordingTransitioning) {
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  if (shouldRecord == isRecording) {
    return;
  }
  
  _isRecordingTransitioning = true;
  try {
    await _toggleRecording(showCountdown: false, suppressSnackbars: true);
  } finally {
    _isRecordingTransitioning = false;
  }
}
```

### Fix 2: Return Async Command Status

Automation commands should return when operation **completes**, not when it **starts**:

```dart
"start_recording": (payload) async {
  await _ensureRecordingState(shouldRecord: true);
  // Wait for recording to actually start
  await _waitForRecordingState(true, timeout: Duration(seconds: 30));
  return AutomationBridge.instance.buildSessionSnapshot();
},
```

### Fix 3: Save Video on Session End

When ending a session while recording:

```dart
Future<void> _endCurrentSession({...}) async {
  // If recording, stop and save first
  if (isRecording) {
    LogService.instance.registerLog("Stopping active recording before ending session");
    await _stopMasterRecordingVideo();
  }
  
  // Then end session
  await SessionManager.instance.endSession();
}
```

### Fix 4: Update Test Scenario Timing

```json
{
  "name": "start-recording",
  "action": "command",
  "command": "start_recording"
},
{
  "name": "wait-for-recording-ready",
  "action": "await",
  "path": "/session",
  "condition": {
    "field": "isRecording",
    "value": true
  },
  "timeout": 30.0
},
{
  "name": "sleep-while-recording",
  "action": "sleep",
  "duration": 10.0  // ✅ Longer recording
},
{
  "name": "stop-recording",
  "action": "command",
  "command": "stop_recording"
},
{
  "name": "wait-for-recording-stopped",
  "action": "await",
  "path": "/session",
  "condition": {
    "field": "videoCount",
    "operator": ">",
    "value": 0
  },
  "timeout": 10.0
}
```

### Fix 5: Add isRecording to Session Snapshot

```dart
Map<String, dynamic> buildSessionSnapshot() {
  return {
    ...
    "isRecording": _masterScreen?.isRecording ?? false,
    ...
  };
}
```

## Impact

### Current State
- ✅ Photo capture: **Working**
- ✅ Photo upload: **Working**
- ❌ Video capture: **Broken** (timing race condition)
- ❌ Video upload: **N/A** (no videos to upload)

### Test Results
- **12/13 automation steps passed**
- **1 critical failure:** Video recording
- **Photos uploaded successfully:** 2/2
- **Videos uploaded:** 0 (expected at least 1)

## Next Steps

1. **Immediate:** Implement Fix #3 (save video on session end)
2. **Short-term:** Implement Fix #1 (async state tracking)
3. **Medium-term:** Implement Fix #2 (async command completion)
4. **Long-term:** Optimize camera initialization time

## Test Verification

After fixes, re-run orchestrator with:
```bash
python3 scripts/multi_device_orchestrator.py \
  --serials emulator-5554:master,emulator-5556:slave,emulator-5558:slave \
  --manifest automation_scenarios/quad_smoke_extended_fixed.json \
  --scenario quad_demo
```

Expected outcome:
- ✅ Photos uploaded: 2+
- ✅ Videos uploaded: 1+ (FIXED)
- ✅ Portal shows video files with proper metadata
