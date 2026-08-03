#!/usr/bin/env python3
"""Run the exact MP-3 resolver on an iOS simulator without Foundation Models."""

import argparse
import gzip
import json
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLANNER = (
    ROOT
    / "Ayura"
    / "AI"
    / "MealPlanning"
    / "USDAWeeklyMealPlanner.swift"
)
CORPUS = ROOT / "ayurveda-data" / "tests" / "resolution-goldens.json"
ARTIFACT_PARTS = [
    ROOT / "Ayura" / "preseeded_db.store.gz.part-aa",
    ROOT / "Ayura" / "preseeded_db.store.gz.part-ab",
]
BUNDLE_ID = "com.ayura.mp3-resolution-gate"


def checked(arguments, **kwargs):
    return subprocess.run(
        arguments,
        check=True,
        capture_output=True,
        text=True,
        **kwargs,
    )


def booted_simulator(explicit_udid):
    devices = json.loads(checked(["xcrun", "simctl", "list", "devices", "-j"]).stdout)
    for runtime_devices in devices["devices"].values():
        for device in runtime_devices:
            if device.get("state") != "Booted":
                continue
            if explicit_udid is None or device["udid"] == explicit_udid:
                return device
    raise RuntimeError("No matching booted iOS simulator")


def production_helper():
    source = PLANNER.read_text(encoding="utf-8")
    start_marker = "// MP3_TESTABLE_BEGIN"
    end_marker = "// MP3_TESTABLE_END"
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise RuntimeError("MP-3 helper markers are not unique")
    helper = source.split(start_marker, 1)[1].split(end_marker, 1)[0]
    if "FoundationModels" in helper or "LanguageModelSession" in helper:
        raise RuntimeError("Resolver helper unexpectedly references a system model")
    return helper


def write_catalog(store_path, destination):
    compressed = b"".join(part.read_bytes() for part in ARTIFACT_PARTS)
    store_path.write_bytes(gzip.decompress(compressed))
    with sqlite3.connect(store_path) as connection:
        payload_data = connection.execute(
            """
            SELECT ZPAYLOADDATA FROM ZSEARCHINDEXCACHE
            WHERE ZKEY = 'main' AND ZVERSION = 10
            """
        ).fetchone()[0]
        profile_rows = connection.execute(
            "SELECT ZID, ZFOODID, ZENGINEEXCLUDED, ZKIND FROM ZAYURVEDAPROFILE"
        ).fetchall()
        link_rows = connection.execute(
            "SELECT ZFDCID, ZDRAVYAPROFILEID, ZTIER FROM ZAYURVEDALINK"
        ).fetchall()

    payload = json.loads(payload_data)
    direct_ids = {
        food_id for _, food_id, _, kind in profile_rows if kind != "catalog"
    }
    catalog_ids = {
        food_id for _, food_id, _, kind in profile_rows if kind == "catalog"
    }
    excluded_profile_ids = {
        profile_id for profile_id, _, excluded, _ in profile_rows if excluded
    }
    excluded_food_ids = {
        food_id for _, food_id, excluded, _ in profile_rows if excluded
    }
    link_tiers = {}
    for food_id, profile_id, tier in link_rows:
        link_tiers[food_id] = tier
        if profile_id in excluded_profile_ids:
            excluded_food_ids.add(food_id)

    candidates = []
    for food in payload["compactFoods"]:
        food_id = food["id"]
        if food_id in excluded_food_ids:
            continue
        if food_id in direct_ids:
            tier = "classical"
        elif food_id in catalog_ids:
            tier = "derived"
        elif food_id in link_tiers:
            tier = "derived" if link_tiers[food_id] == "derived" else "classical"
        else:
            tier = "estimated"
        candidates.append(
            {
                "id": food_id,
                "name": food["name"],
                "isRecipe": food["isRecipe"],
                "tier": tier,
            }
        )
    destination.write_text(
        json.dumps(candidates, ensure_ascii=False, sort_keys=True),
        encoding="utf-8",
    )
    return len(payload["compactFoods"]), len(candidates)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid")
    arguments = parser.parse_args()
    device = booted_simulator(arguments.udid)

    with tempfile.TemporaryDirectory(prefix="mp3-simulator-gate-") as raw_root:
        temporary_root = Path(raw_root)
        app = temporary_root / "MP3ResolutionGate.app"
        app.mkdir()
        executable = app / "MP3ResolutionGate"
        source = temporary_root / "MP3ResolutionGate.swift"
        catalog_count, candidate_count = write_catalog(
            temporary_root / "preseed.store",
            app / "catalog.json",
        )
        shutil.copy2(CORPUS, app / CORPUS.name)

        source.write_text(
            "import UIKit\n"
            + production_helper()
            + r'''

struct SimulatorGoldenCorpus: Codable {
    let cases: [SimulatorGoldenCase]
}

struct SimulatorGoldenCase: Codable {
    let concept: String
    let expectUnresolved: Bool?
}

struct SimulatorGateResult: Codable {
    let totalCases: Int
    let positiveResolved: Int
    let controlsUnresolved: Int
    let resolverUsesSystemModel: Bool
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        do {
            let decoder = JSONDecoder()
            let candidates = try decoder.decode(
                [PlannerResolutionCandidate].self,
                from: Data(
                    contentsOf: Bundle.main.url(
                        forResource: "catalog",
                        withExtension: "json"
                    )!
                )
            )
            let corpus = try decoder.decode(
                SimulatorGoldenCorpus.self,
                from: Data(
                    contentsOf: Bundle.main.url(
                        forResource: "resolution-goldens",
                        withExtension: "json"
                    )!
                )
            )
            let prepared = PlannerDeterministicFoodResolver.prepare(candidates)
            var positiveResolved = 0
            var controlsUnresolved = 0
            for golden in corpus.cases {
                let decision = PlannerDeterministicFoodResolver.resolve(
                    concept: golden.concept,
                    candidates: prepared
                )
                if golden.expectUnresolved == true {
                    if decision == nil { controlsUnresolved += 1 }
                } else if decision != nil {
                    positiveResolved += 1
                }
            }
            let result = SimulatorGateResult(
                totalCases: corpus.cases.count,
                positiveResolved: positiveResolved,
                controlsUnresolved: controlsUnresolved,
                resolverUsesSystemModel: false
            )
            let destination = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("mp3-simulator-result.json")
            try JSONEncoder().encode(result).write(to: destination)
        } catch {
            fatalError("MP-3 simulator gate failed: \(error)")
        }
        return true
    }
}
''',
            encoding="utf-8",
        )
        plist = {
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "MP3ResolutionGate",
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "MP3ResolutionGate",
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
                "-target",
                "arm64-apple-ios26.0-simulator",
                str(source),
                "-framework",
                "UIKit",
                "-o",
                str(executable),
            ]
        )
        linked_frameworks = checked(["otool", "-L", str(executable)]).stdout
        if "FoundationModels" in linked_frameworks:
            raise RuntimeError("Simulator gate unexpectedly links FoundationModels")
        checked(["codesign", "--force", "--sign", "-", str(app)])

        subprocess.run(
            ["xcrun", "simctl", "terminate", device["udid"], BUNDLE_ID],
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["xcrun", "simctl", "uninstall", device["udid"], BUNDLE_ID],
            capture_output=True,
            text=True,
        )
        checked(["xcrun", "simctl", "install", device["udid"], str(app)])
        checked(["xcrun", "simctl", "launch", device["udid"], BUNDLE_ID])
        data_container = Path(
            checked(
                [
                    "xcrun",
                    "simctl",
                    "get_app_container",
                    device["udid"],
                    BUNDLE_ID,
                    "data",
                ]
            ).stdout.strip()
        )
        result_path = (
            data_container / "Documents" / "mp3-simulator-result.json"
        )
        for _ in range(120):
            if result_path.exists():
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("Simulator resolver did not produce evidence")

        result = json.loads(result_path.read_text(encoding="utf-8"))
        if result != {
            "controlsUnresolved": 3,
            "positiveResolved": 56,
            "resolverUsesSystemModel": False,
            "totalCases": 59,
        }:
            raise RuntimeError(f"Unexpected simulator result: {result}")
        print(
            json.dumps(
                {
                    "candidateCount": candidate_count,
                    "catalogCount": catalog_count,
                    "device": device,
                    "foundationModelsLinked": False,
                    "result": result,
                },
                indent=2,
                sort_keys=True,
            )
        )


if __name__ == "__main__":
    main()
