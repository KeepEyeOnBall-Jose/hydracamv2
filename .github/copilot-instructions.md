# GitHub Copilot Instructions for HydraCamV2

## Project Overview

HydraCamV2 is a Flutter-based application designed for multi-device camera automation, supporting Android and iOS platforms. The project includes automation scripts for testing across multiple devices and emulators.

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