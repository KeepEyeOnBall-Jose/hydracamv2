# GitHub Copilot Instructions for HydraCamV2

## Project Overview

HydraCamV2 is a Flutter-based application designed for multi-device camera automation, supporting Android and iOS platforms. The project includes automation scripts for testing across multiple devices and emulators.

## Turn Completion Protocol (MANDATORY)

**Before handing off control back to the user, EVERY turn MUST complete these two steps:**

### 1. Validation Tests (Binary Pass/Fail)

Define and execute **at least 3 specific, binary tests** that verify the change works:

| Test | Command/URL | Expected Result |
|------|-------------|-----------------|
| Test 1 | `flutter analyze` | No issues found |
| Test 2 | `flutter test test/specific_test.dart` | All tests pass |
| Test 3 | `curl -s http://localhost:PORT/endpoint` | Specific success criteria |

**Each test must be:**
- **Specific**: Exact command to check
- **Binary**: Clear pass/fail (not "looks good")
- **Executed**: Actually run before handoff, not just proposed

**Do NOT hand off until all tests pass.**

### 2. Next Action Proposal (Agent Self-Planning)

After completing the current task, the agent MUST **propose the next logical step IT can take** to advance the development process toward long-term goals. This is NOT a suggestion for the human—it's the agent's forward-looking plan for what IT will do next when given the opportunity.

**The proposal should anticipate one of these development patterns:**
- **Implementation turns**: Build the next feature or fix
- **Plan/verification turns**: Validate assumptions, check test coverage, audit code quality
- **Hypothesis validation turns**: Test an approach before committing to it
- **Investigation turns**: Gather context needed for the next implementation
- **Cleanup/refactor turns**: Address technical debt blocking progress

**Selection criteria (in priority order):**
1. What unblocks the most progress toward long-term project goals?
2. What reduces uncertainty or risk for upcoming work?
3. What provides compounding value for future development?

Format:
```
**Next step I'll take:** [One sentence describing the agent's next action]
**Advances goal:** [Which long-term project goal this serves]
**Turn type:** [implementation | verification | hypothesis | investigation | cleanup]
**Starting point:** [File, command, or API to begin with]
```

**Examples of good proposals:**
- "Next step I'll take: Add integration tests for the new ball-tracking API endpoints" (verification)
- "Next step I'll take: Investigate why pose extraction fails on videos > 10 minutes" (investigation)  
- "Next step I'll take: Implement the homography calculation service" (implementation)
- "Next step I'll take: Validate that the new schema migration is backwards-compatible" (hypothesis)

---

## Coding Guidelines

### Starting Android Emulators

When starting Android emulators, **do not use raw `nohup` commands with redirects to `/tmp`**, as these require manual approval and can cause issues in automated environments.

Instead, wrap emulator startup calls into a meaningful action using the `EmulatorManager` class from `scripts/emulator_manager.py`. This class handles the command execution with proper logging to project-specific log files.

Example usage:

```python
from scripts.emulator_manager import EmulatorManager

manager = EmulatorManager()
manager.start_emulator('Pixel_7', 5562)
```

When running Android SDK tools (sdkmanager, avdmanager, emulator) prefer changing directory into the SDK installation and invoking the tool from there instead of requiring callers to set `ANDROID_SDK_ROOT` in the environment. Setting environment variables interactively can interrupt scripted flows; a simple `cd` keeps commands copy-pastable and reliable.

Example (macOS, SDK under `~/Library/Android/sdk`):

```bash
cd ~/Library/Android/sdk/cmdline-tools/latest/bin
./sdkmanager --install "platform-tools" "emulator" "system-images;android-34;google_apis_playstore;arm64-v8a"
./avdmanager create avd --name Pixel_7 --package "system-images;android-34;google_apis_playstore;arm64-v8a" --device pixel_7
```

If you prefer to run the tools by absolute path from the project root, that is also fine; the important part is to avoid requiring users to manually export environment variables as the first step.

The `EmulatorManager` class constructs and executes a single shell command internally, ensuring consistent and safe emulator management.

### Building and Testing

- Use the provided VS Code tasks for Flutter operations (clean, get dependencies, build APK, run tests).
- For iOS builds, follow the instructions in `iOS_BUILD_FIX.md` and use the scripts in the `scripts/` directory.
- Run integration tests using the files in `integration_test/`.

### Automation and Multi-Device Testing

- Utilize the `multi_device_orchestrator.py` script for orchestrating tests across multiple devices.
- Automation scenarios are defined in `automation_scenarios/`.
- Results are stored in `automation_runs/`.

### General Best Practices

- Avoid direct shell commands with complex redirections; prefer wrapper classes or scripts.
- When a task requires iterating over devices or chaining multiple shell commands, write a tiny one-off Python helper (committed under `scripts/` or run inline) instead of inlining complex bash pipelines or redirections. This keeps logs readable and avoids interactive prompt issues.
- Log outputs to project-relative directories (e.g., `logs/`) instead of system paths like `/tmp`.
- Ensure all new code includes appropriate error handling and logging.

### Shell Command Best Practices (CRITICAL)

**NEVER run complex shell commands directly in the terminal.** Complex commands with:
- Multiple pipes (`|`)
- Nested quotes (single and double)
- Subshells (`$(...)` or backticks)
- Python inline code (`python3 -c "..."`)
- Long command chains with `&&` or `;`

**MUST be written to a script file first and then executed.**

**Why:** Shell quoting is extremely error-prone when commands are constructed programmatically. Mismatched quotes cause the terminal to hang waiting for input, requiring user intervention to cancel.

**Correct approach:**
1. Write the command to a temporary script file (e.g., `scripts/temp_check_devices.sh`)
2. Make it executable (`chmod +x`)
3. Run the script file

**Example - WRONG:**
```bash
# DO NOT DO THIS - quoting will break!
curl -s http://127.0.0.1:5900/session | python3 -c "import sys, json; d=json.load(sys.stdin); print(f\"Master: {d['deviceType']}\")"
```

**Example - CORRECT:**
```bash
# Step 1: Write to file
cat > scripts/check_device_status.sh << 'EOF'
#!/bin/bash
echo "=== Master (5554) ==="
curl -s http://127.0.0.1:5900/session | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(f"Device Type: {d[\"deviceType\"]}")
'
EOF

# Step 2: Make executable and run
chmod +x scripts/check_device_status.sh
./scripts/check_device_status.sh
```

**Alternative - Use Python scripts:**
For commands involving JSON processing, curl, or complex logic, write a Python script instead:

```python
# scripts/check_device_status.py
import requests

response = requests.get('http://127.0.0.1:5900/session')
data = response.json()
print(f"Device Type: {data['deviceType']}")
```

Then run: `python3 scripts/check_device_status.py`

**Key Rules:**
- If a command has more than 2 pipes OR any Python inline code → Write to file
- If a command has nested quotes (both ' and ") → Write to file
- If a command spans multiple lines with && → Write to file
- Simple commands (single curl, single adb, etc.) are OK to run directly