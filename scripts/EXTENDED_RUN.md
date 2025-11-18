Run a single extended manifest with one emulator (example)

This prepares the app and invokes the orchestrator directly using the extended manifest `automation_scenarios/quad_smoke_extended.json`.

1) Prepare the device (example for emulator-5554):

```bash
# Force-stop and launch the app with automation extras
adb -s emulator-5554 shell cmd appops set com.amaia23.hydracam RECORD_AUDIO ignore
adb -s emulator-5554 shell cmd appops set com.amaia23.hydracam CAPTURE_AUDIO_OUTPUT ignore
adb -s emulator-5554 shell cmd appops set com.amaia23.hydracam CAPTURE_AUDIO_HOTWORD ignore
adb -s emulator-5554 shell am force-stop com.amaia23.hydracam
adb -s emulator-5554 shell am start -n com.amaia23.hydracam/.MainActivity --ez HYDRACAM_AUTOMATION true --es role master
# wait for app to start
sleep 15
```

2) Run the orchestrator directly (example):

```bash
python3 scripts/multi_device_orchestrator.py --serials emulator-5554:master --manifest automation_scenarios/quad_smoke_extended.json --scenario quad_smoke_extended
```

Notes:
- Adjust serials list if running more devices.
- The manifest uses longer post-recording sleeps and an additional await so the device uploader has time to detect and upload media.
- If you want `run_manifest_matrix.py` to execute this manifest automatically, I can update that helper to accept a `--manifest` flag.
