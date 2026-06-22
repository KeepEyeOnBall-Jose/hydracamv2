#!/usr/bin/env python3
"""Check HydraCam wearable replay readiness gates.

The default "mock" mode verifies the local emulator/simulator lane. The "dat"
mode additionally checks the repo-controlled DAT registration and dependency
boundary. Use "--check-network" in dat mode for the external GitHub Packages
access gate needed before physical Meta DAT integration.
"""

from __future__ import annotations

import argparse
import base64
import os
import plistlib
import ssl
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


ANDROID_DAT_POM_URL = (
    "https://maven.pkg.github.com/facebook/meta-wearables-dat-android/"
    "com/meta/wearable/mwdat-core/0.7.0/mwdat-core-0.7.0.pom"
)


@dataclass
class CheckResult:
    label: str
    ok: bool
    detail: str = ""

    @property
    def prefix(self) -> str:
        return "PASS" if self.ok else "FAIL"


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    results = run_checks(
        root=root,
        mode=args.mode,
        env=os.environ,
        check_network=args.check_network,
        timeout_seconds=args.timeout_seconds,
    )
    for result in results:
        suffix = f" - {result.detail}" if result.detail else ""
        print(f"{result.prefix}: {result.label}{suffix}")
    failures = [result for result in results if not result.ok]
    if failures:
        print(f"wearable replay readiness failed: {len(failures)} failing check(s)")
        return 1
    print(f"wearable replay readiness passed: {len(results)} check(s)")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check HydraCam wearable replay readiness.",
    )
    parser.add_argument(
        "mode",
        nargs="?",
        default="mock",
        choices=("mock", "dat"),
        help=(
            "mock checks emulator/simulator readiness; dat adds repo-controlled "
            "Meta DAT registration and dependency-boundary gates."
        ),
    )
    parser.add_argument(
        "--root",
        default=Path(__file__).resolve().parents[1],
        help="HydraCam repository root.",
    )
    parser.add_argument(
        "--check-network",
        action="store_true",
        help=(
            "In dat mode, verify external Android DAT GitHub Package access "
            "with GITHUB_TOKEN or GH_TOKEN."
        ),
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=10.0,
        help="Network timeout for --check-network.",
    )
    return parser.parse_args(argv)


def run_checks(
    *,
    root: Path,
    mode: str,
    env: Mapping[str, str],
    check_network: bool,
    timeout_seconds: float,
) -> list[CheckResult]:
    results: list[CheckResult] = []
    results.extend(check_required_files(root))
    results.extend(check_android_dat_manifest(root))
    results.extend(check_ios_dat_plist(root))
    results.extend(check_watch_module(root))
    results.extend(check_mock_fallback_contract(root))
    results.extend(check_upload_handoff_contract(root))
    if mode == "dat":
        results.extend(check_dat_dependency_boundary(root))
        if check_network:
            results.append(check_android_package_access(env, timeout_seconds))
    return results


def check_required_files(root: Path) -> list[CheckResult]:
    required = [
        "lib/models/wearable_replay.dart",
        "lib/services/wearable_replay_bridge_service.dart",
        "lib/services/wearable_replay_service.dart",
        "lib/services/wearable_replay_simulation_service.dart",
        "lib/services/wearable_replay_upload_service.dart",
        "integration_test/wearable_replay_channel_test.dart",
        "test/models/wearable_replay_test.dart",
        "test/services/wearable_replay_bridge_service_test.dart",
        "test/services/wearable_replay_service_test.dart",
        "test/services/wearable_replay_simulation_service_test.dart",
        "test/services/wearable_replay_upload_service_test.dart",
        "test/services/wearable_replay_live_upload_test.dart",
        "docs/control/wearable-replay-integration-plan.md",
    ]
    return [
        CheckResult(f"{relative} exists", (root / relative).is_file())
        for relative in required
    ]


def check_android_dat_manifest(root: Path) -> list[CheckResult]:
    manifest = read_text(root / "android/app/src/main/AndroidManifest.xml")
    build_gradle = read_text(root / "android/app/build.gradle")
    return [
        contains_check(
            "Android declares BLUETOOTH_CONNECT for DAT",
            manifest,
            'android.permission.BLUETOOTH_CONNECT',
        ),
        contains_check(
            "Android declares DAT application id metadata",
            manifest,
            'com.meta.wearable.mwdat.APPLICATION_ID',
        ),
        contains_check(
            "Android declares DAT analytics opt-out metadata",
            manifest,
            'com.meta.wearable.mwdat.ANALYTICS_OPT_OUT',
        ),
        contains_check(
            "Android declares DAT callback scheme intent filter",
            manifest,
            '${mwdatRedirectScheme}',
        ),
        contains_check(
            "Android Gradle defines DAT redirect scheme placeholder",
            build_gradle,
            'manifestPlaceholders["mwdatRedirectScheme"]',
        ),
        contains_check(
            "Android Gradle defaults DAT application id to developer mode",
            build_gradle,
            'manifestPlaceholders["mwdatApplicationId"] = "0"',
        ),
    ]


def check_ios_dat_plist(root: Path) -> list[CheckResult]:
    plist_path = root / "ios/Runner/Info.plist"
    try:
        plist = plistlib.loads(plist_path.read_bytes())
    except Exception as error:  # pragma: no cover - exercised by CLI behavior.
        return [CheckResult("iOS Info.plist parses", False, str(error))]

    url_schemes = [
        scheme
        for url_type in plist.get("CFBundleURLTypes", [])
        for scheme in url_type.get("CFBundleURLSchemes", [])
    ]
    mwdat = plist.get("MWDAT", {})
    background_modes = plist.get("UIBackgroundModes", [])
    protocols = plist.get("UISupportedExternalAccessoryProtocols", [])
    query_schemes = plist.get("LSApplicationQueriesSchemes", [])
    return [
        CheckResult(
            "iOS declares DAT callback scheme",
            "com.keepeyeonball.mwdat" in url_schemes,
        ),
        CheckResult(
            "iOS MWDAT developer MetaAppID is configured",
            mwdat.get("MetaAppID") == "0",
        ),
        CheckResult(
            "iOS MWDAT callback URL is configured",
            mwdat.get("AppLinkURLScheme") == "com.keepeyeonball.mwdat://",
        ),
        CheckResult(
            "iOS MWDAT analytics opt-out is configured",
            bool(mwdat.get("Analytics", {}).get("OptOut")) is True,
        ),
        CheckResult(
            "iOS allows Meta AI callback query scheme",
            "fb-viewapp" in query_schemes,
        ),
        CheckResult(
            "iOS declares Meta wearable external accessory protocol",
            "com.meta.ar.wearable" in protocols,
        ),
        CheckResult(
            "iOS declares Bluetooth/external accessory background modes",
            "bluetooth-peripheral" in background_modes
            and "external-accessory" in background_modes,
        ),
        CheckResult(
            "iOS declares Bluetooth usage description",
            bool(plist.get("NSBluetoothAlwaysUsageDescription")),
        ),
    ]


def check_watch_module(root: Path) -> list[CheckResult]:
    health_source = read_text(
        root
        / "android/wearable/src/main/kotlin/com/amaia23/hydracam/wearable/"
        "HealthServicesWearTelemetrySource.kt"
    )
    manifest = read_text(root / "android/wearable/src/main/AndroidManifest.xml")
    build_gradle = read_text(root / "android/wearable/build.gradle")
    return [
        contains_check(
            "Wear module depends on Wear OS Health Services",
            build_gradle,
            "androidx.health:health-services-client",
        ),
        contains_check(
            "Wear module declares BODY_SENSORS",
            manifest,
            "android.permission.BODY_SENSORS",
        ),
        contains_check(
            "Wear telemetry registers MeasureClient heart-rate callback",
            health_source,
            "registerMeasureCallback",
        ),
        contains_check(
            "Wear telemetry merges Android motion sensors",
            health_source,
            "Sensor.TYPE_ACCELEROMETER",
        ),
    ]


def check_mock_fallback_contract(root: Path) -> list[CheckResult]:
    bridge = read_text(root / "lib/services/wearable_replay_bridge_service.dart")
    simulation = read_text(root / "lib/services/wearable_replay_simulation_service.dart")
    android = read_text(
        root / "android/app/src/main/kotlin/com/amaia23/hydracam/MainActivity.kt"
    )
    ios = read_text(root / "ios/Runner/AppDelegate.swift")
    integration = read_text(root / "integration_test/wearable_replay_channel_test.dart")
    return [
        contains_check(
            "Dart bridge exposes rolling POV fallback capability",
            bridge,
            "supportsRollingPovFallback",
        ),
        contains_check(
            "Simulation falls back to rollingHighlight when DAT is unavailable",
            simulation,
            "PovCaptureMode.rollingHighlight",
        ),
        contains_check(
            "Simulation records fallback reason",
            simulation,
            "meta_dat_unavailable_simulated_rolling_buffer",
        ),
        contains_check(
            "Android native bridge advertises rolling fallback",
            android,
            '"supportsRollingPovFallback" to true',
        ),
        contains_check(
            "iOS native bridge advertises rolling fallback",
            ios,
            '"supportsRollingPovFallback": true',
        ),
        contains_check(
            "Native integration test asserts rollingHighlight",
            integration,
            "PovCaptureMode.rollingHighlight",
        ),
    ]


def check_upload_handoff_contract(root: Path) -> list[CheckResult]:
    upload_service = read_text(root / "lib/services/wearable_replay_upload_service.dart")
    upload_test = read_text(root / "test/services/wearable_replay_upload_service_test.dart")
    live_upload_test = read_text(
        root / "test/services/wearable_replay_live_upload_test.dart"
    )
    simulation_test = read_text(
        root / "test/services/wearable_replay_simulation_service_test.dart"
    )
    pubspec = read_text(root / "pubspec.yaml")
    control_doc = read_text(root / "docs/control/wearable-replay-integration-plan.md")
    return [
        contains_check(
            "Upload service depends on http_parser for multipart MIME types",
            pubspec,
            "http_parser:",
        ),
        contains_check(
            "Upload service imports MediaType",
            upload_service,
            'package:http_parser/http_parser.dart',
        ),
        contains_check(
            "Upload service parses POV media count",
            upload_service,
            'povMediaCount: _intValue(json["povMediaCount"])',
        ),
        contains_check(
            "Upload service attaches multipart content types",
            upload_service,
            "contentType: _contentTypeFor(file.path)",
        ),
        contains_check(
            "Upload service includes calibration sidecars",
            upload_service,
            '"calibrationFiles"',
        ),
        contains_check(
            "Upload service maps JSONL sidecars to NDJSON MIME",
            upload_service,
            'MediaType("application", "x-ndjson")',
        ),
        contains_check(
            "Upload service maps MP4 POV media to video/mp4",
            upload_service,
            'MediaType("video", "mp4")',
        ),
        contains_check(
            "Upload unit test asserts POV media MIME",
            upload_test,
            "povMediaFiles:pov-1.mp4:video/mp4",
        ),
        contains_check(
            "Live upload proof is gated by HYDRACAM_WEARABLE_LIVE_UPLOAD",
            live_upload_test,
            "HYDRACAM_WEARABLE_LIVE_UPLOAD",
        ),
        contains_check(
            "Live upload proof writes a generated wearable manifest",
            live_upload_test,
            "writeUploadManifest(sessionGuid)",
        ),
        contains_check(
            "Live upload proof records clap-flash calibration sidecar",
            live_upload_test,
            "recordSyncCalibration",
        ),
        contains_check(
            "Live upload proof verifies <=50 ms calibration target",
            live_upload_test,
            "targetAlignmentMs: 50",
        ),
        contains_check(
            "Live upload proof posts generated manifest to media-timeline",
            live_upload_test,
            "uploadService.uploadManifest",
        ),
        contains_check(
            "Live upload proof verifies media-timeline POV media count",
            live_upload_test,
            "expect(uploadResult.povMediaCount, 1)",
        ),
        contains_check(
            "Live upload proof verifies rolling-highlight replay metadata",
            live_upload_test,
            'expect(replay["captureMode"], "rollingHighlight")',
        ),
        contains_check(
            "Simulation proof sends watch haptic feedback",
            simulation_test,
            '"watchHaptic"',
        ),
        contains_check(
            "Simulation proof sends glasses audio feedback",
            simulation_test,
            '"glassesAudio"',
        ),
        contains_check(
            "Live upload proof persists both feedback channels",
            live_upload_test,
            'expect(manifest["feedbackFiles"], hasLength(2))',
        ),
        contains_check(
            "Control doc records live upload proof command",
            control_doc,
            "HYDRACAM_WEARABLE_LIVE_UPLOAD=true",
        ),
    ]


def check_dat_dependency_boundary(root: Path) -> list[CheckResult]:
    android_build = read_text(root / "android/app/build.gradle")
    ios_podfile = read_text(root / "ios/Podfile")
    return [
        CheckResult(
            "Default Android build keeps private Meta DAT SDK artifacts gated",
            "com.meta.wearable:mwdat-" not in android_build,
        ),
        CheckResult(
            "Default iOS build keeps private Meta DAT SDK artifacts gated",
            "MWDATCore" not in ios_podfile
            and "MWDATCamera" not in ios_podfile
            and "MWDATMockDevice" not in ios_podfile,
        ),
        contains_check(
            "Control doc records DAT dependencies as hardware-lane gated",
            read_text(root / "docs/control/wearable-replay-integration-plan.md"),
            "Do not add `mwdat-core`",
        ),
    ]


def check_android_package_access(
    env: Mapping[str, str],
    timeout_seconds: float,
) -> CheckResult:
    token = env.get("GITHUB_TOKEN") or env.get("GH_TOKEN")
    if not token:
        return CheckResult(
            "Android DAT GitHub Package access",
            False,
            "set GITHUB_TOKEN or GH_TOKEN before --check-network",
        )
    request = urllib.request.Request(ANDROID_DAT_POM_URL, method="GET")
    auth = base64.b64encode(f":{token}".encode("utf-8")).decode("ascii")
    request.add_header("Authorization", f"Basic {auth}")
    try:
        with urllib.request.urlopen(
            request,
            timeout=timeout_seconds,
            context=build_ssl_context(),
        ) as response:
            return CheckResult(
                "Android DAT GitHub Package access",
                200 <= response.status < 300,
                f"HTTP {response.status}",
            )
    except urllib.error.HTTPError as error:
        return CheckResult(
            "Android DAT GitHub Package access",
            False,
            f"HTTP {error.code}",
        )
    except urllib.error.URLError as error:
        return CheckResult(
            "Android DAT GitHub Package access",
            False,
            f"URLError: {error.reason}",
        )
    except Exception as error:
        return CheckResult(
            "Android DAT GitHub Package access",
            False,
            error.__class__.__name__,
        )


def build_ssl_context() -> ssl.SSLContext:
    try:
        import certifi  # type: ignore[import-not-found]

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        return ssl.create_default_context()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def contains_check(label: str, text: str, needle: str) -> CheckResult:
    return CheckResult(label, needle in text)


if __name__ == "__main__":
    sys.exit(main())
