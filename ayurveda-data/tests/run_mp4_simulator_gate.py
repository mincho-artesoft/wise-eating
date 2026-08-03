#!/usr/bin/env python3
"""Run MP-4's complete availability-to-fallback parse path on a simulator."""

import argparse
import json
import plistlib
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REQUEST = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "MealPlanRequest.swift"
)
BUNDLE_ID = "com.ayura.mp4-intent-gate"


def checked(arguments, **kwargs):
    return subprocess.run(
        arguments,
        check=True,
        capture_output=True,
        text=True,
        **kwargs,
    )


def booted_simulator(explicit_udid):
    devices = json.loads(
        checked(["xcrun", "simctl", "list", "devices", "-j"]).stdout
    )
    for runtime_devices in devices["devices"].values():
        for device in runtime_devices:
            if device.get("state") != "Booted":
                continue
            if explicit_udid is None or device["udid"] == explicit_udid:
                return device
    raise RuntimeError("No matching booted iOS simulator")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid")
    arguments = parser.parse_args()
    device = booted_simulator(arguments.udid)
    udid = device["udid"]

    with tempfile.TemporaryDirectory(prefix="mp4-simulator-gate-") as raw_root:
        temporary_root = Path(raw_root)
        app = temporary_root / "MP4IntentGate.app"
        app.mkdir()
        executable = app / "MP4IntentGate"
        source = temporary_root / "MP4IntentGate.swift"
        source.write_text(
            r'''
import Foundation
import UIKit

struct SimulatorGateResult: Codable {
    let availability: String
    let usedFallback: Bool
    let modelCalls: Int
    let days: Int
    let allergen: String?
    let deterministic: Bool
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        Task { @MainActor in
            let availability = "unavailable:no-FoundationModels-build"

            var modelCalls = 0
            let prompt = "3 day vegan plan, no peanuts"
            let first = await MealPlanIntentCoordinator.parse(
                prompts: [prompt],
                modelAvailable: false,
                modelResponse: { _ in
                    modelCalls += 1
                    return ParsedRequest()
                },
                onModelCall: { _, _ in }
            )
            let second = await MealPlanIntentCoordinator.parse(
                prompts: [prompt],
                modelAvailable: false,
                modelResponse: { _ in
                    modelCalls += 1
                    return ParsedRequest()
                },
                onModelCall: { _, _ in }
            )
            let sanitized = RequestSanitizer.sanitize(
                first.request,
                computedMaintenanceKcal: 2_000
            ).request
            let result = SimulatorGateResult(
                availability: availability,
                usedFallback: first.usedFallback,
                modelCalls: modelCalls,
                days: sanitized.days,
                allergen: sanitized.allergens.first?.rawValue,
                deterministic: first == second
            )
            do {
                let destination = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0].appendingPathComponent("mp4-simulator-result.json")
                try JSONEncoder().encode(result).write(to: destination)
            } catch {
                fatalError("MP-4 simulator result write failed: \(error)")
            }
        }
        return true
    }
}
''',
            encoding="utf-8",
        )
        plist = {
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "MP4IntentGate",
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "MP4IntentGate",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSRequiresIPhoneOS": True,
            "MinimumOSVersion": "26.0",
            "UIDeviceFamily": [1],
            "UILaunchScreen": {},
        }
        with (app / "Info.plist").open("wb") as plist_file:
            plistlib.dump(plist, plist_file, sort_keys=True)

        checked(
            [
                "xcrun",
                "--sdk",
                "iphonesimulator",
                "swiftc",
                "-O",
                "-parse-as-library",
                "-D",
                "MP4_NO_FOUNDATION_MODELS",
                "-target",
                "arm64-apple-ios26.0-simulator",
                str(REQUEST),
                str(source),
                "-framework",
                "UIKit",
                "-o",
                str(executable),
            ]
        )
        linked_frameworks = checked(["otool", "-L", str(executable)]).stdout
        if "FoundationModels" in linked_frameworks:
            raise RuntimeError(
                "No-model simulator gate unexpectedly links FoundationModels"
            )
        checked(["codesign", "--force", "--sign", "-", str(app)])
        subprocess.run(
            ["xcrun", "simctl", "terminate", udid, BUNDLE_ID],
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["xcrun", "simctl", "uninstall", udid, BUNDLE_ID],
            capture_output=True,
            text=True,
        )
        checked(["xcrun", "simctl", "install", udid, str(app)])
        checked(["xcrun", "simctl", "launch", udid, BUNDLE_ID])

        result_path = None
        for _ in range(100):
            container = checked(
                ["xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "data"]
            ).stdout.strip()
            candidate = (
                Path(container)
                / "Documents"
                / "mp4-simulator-result.json"
            )
            if candidate.exists():
                result_path = candidate
                break
            time.sleep(0.1)
        if result_path is None:
            raise RuntimeError("MP-4 simulator result did not appear")

        result = json.loads(result_path.read_text(encoding="utf-8"))
        if not result["availability"].startswith("unavailable:"):
            raise RuntimeError(
                "Simulator unexpectedly reports a system model: "
                + result["availability"]
            )
        expected = {
            "usedFallback": True,
            "modelCalls": 0,
            "days": 3,
            "allergen": "peanuts",
            "deterministic": True,
        }
        for key, value in expected.items():
            if result.get(key) != value:
                raise RuntimeError(
                    f"MP-4 simulator gate mismatch for {key}: "
                    f"expected {value!r}, got {result.get(key)!r}"
                )
        print(
            json.dumps(
                {
                    "device": device["name"],
                    "udid": udid,
                    **result,
                },
                sort_keys=True,
            )
        )


if __name__ == "__main__":
    main()
