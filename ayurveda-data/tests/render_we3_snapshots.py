#!/usr/bin/env python3
"""Render and compare WE-3 SwiftUI snapshots on an iOS simulator."""

import argparse
import json
import plistlib
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


ROOT = Path(__file__).resolve().parents[2]
BASELINES = ROOT / "ayurveda-data/tests/snapshots/we3"
BUNDLE_ID = "com.ayurvedaasanayoga.we3snapshots"
SNAPSHOT_NAMES = [
    "ayurveda-light-default.png",
    "ayurveda-dark-default.png",
    "ayurveda-light-accessibility5.png",
    "ayurveda-dark-accessibility5.png",
]

SOURCE_FILES = [
    ROOT / "Ayura/Ayurveda/AyurvedaDisplayMath.swift",
    ROOT / "Ayura/Ayurveda/Views/AyurvedaDisplay.swift",
    ROOT / "Ayura/Ayurveda/Views/AyurvedaSectionView.swift",
    ROOT / "Ayura/Ayurveda/Views/AyurvedaChip.swift",
    ROOT / "Ayura/Ayurveda/Views/ChipGrid.swift",
    ROOT / "Ayura/Ayurveda/Views/DoshaBarsView.swift",
    ROOT / "Ayura/Ayurveda/Views/DoshaScaleSelector.swift",
    ROOT / "Ayura/Food/Views/CustomFlowLayout.swift",
]

COLOR_ASSETS = [
    "AyurvedaPacify.colorset",
    "AyurvedaAggravate.colorset",
    "AyurvedaNeutral.colorset",
    "AyurvedaWarning.colorset",
    "AyurvedaChipTint.colorset",
]

STUBS = r"""
import SwiftData
import SwiftUI

struct FoodItem {
  let id: Int
}

struct AyurvedaLink {
  let tier: String
}

struct AyurvedaModifier {
  let label: String
}

typealias DoshaVPK = (vata: Int, pitta: Int, kapha: Int)

struct AyurvedaEstimate {
  let vpk: DoshaVPK
  let virya: String?
  let gunas: [String]
  let appliedModifiers: [AyurvedaModifier]
}

struct AyurvedaProfile {
  let name: String
  let doshaVata: Int
  let doshaPitta: Int
  let doshaKapha: Int
  let rasa: [String]
  let virya: String?
  let vipaka: String?
  let gunas: [String]
  let viruddha: [String]
  let contraindications: [String]
  let engineExcluded: Bool
  let edible: Bool
  let qualityState: String
  let sanskrit: String?
}

enum AyurvedaResolution: CustomStringConvertible {
  case classical(AyurvedaProfile)
  case recipe(AyurvedaProfile)
  case user(AyurvedaProfile)
  case derived(AyurvedaProfile, AyurvedaLink, [AyurvedaModifier], DoshaVPK)
  case computed(AyurvedaDisplayMath.Computed)
  case estimated(AyurvedaEstimate)
  case none

  var confidence: Double? { 0.75 }
  var description: String { "snapshot fixture" }
}

enum AyurvedaResolver {
  static func resolve(
    for food: FoodItem,
    context: ModelContext
  ) throws -> AyurvedaResolution {
    .none
  }
}

extension View {
  func glassCardStyle(
    cornerRadius: CGFloat = 20,
    useSnapShot: Int? = 1
  ) -> some View {
    background(
      Color(.secondarySystemBackground),
      in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
    }
  }
}
"""

APP_SOURCE = r"""
import SwiftUI
import UIKit

@main
struct WE3SnapshotApp: App {
  @State private var status = "Rendering WE-3 snapshots…"

  var body: some Scene {
    WindowGroup {
      Text(status)
        .font(.headline)
        .padding()
        .task {
          do {
            try renderSnapshots()
            status = "WE-3 snapshots complete"
          } catch {
            status = "Snapshot failure: \(error)"
          }
        }
    }
  }

  @MainActor
  private func renderSnapshots() throws {
    let variants: [(String, ColorScheme, DynamicTypeSize)] = [
      ("ayurveda-light-default.png", .light, .large),
      ("ayurveda-dark-default.png", .dark, .large),
      ("ayurveda-light-accessibility5.png", .light, .accessibility5),
      ("ayurveda-dark-accessibility5.png", .dark, .accessibility5),
    ]
    let documents = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    )[0]

    for (name, scheme, typeSize) in variants {
      let content = VStack(spacing: 0) {
        AyurvedaDisplayCard(display: sample)
          .padding(24)
        Rectangle()
          .fill(Color(.systemBackground))
          .frame(height: 96)
      }
      .frame(width: 760)
      .background(Color(.systemBackground))
      .environment(\.colorScheme, scheme)
      .environment(\.dynamicTypeSize, typeSize)
      .fixedSize(horizontal: false, vertical: true)

      let image = try hierarchyImage(content)
      guard let data = image.pngData() else {
        throw SnapshotError.renderFailed(name)
      }
      try data.write(to: documents.appendingPathComponent(name), options: .atomic)
    }
    try Data("done\n".utf8).write(
      to: documents.appendingPathComponent("WE3-SNAPSHOTS-DONE"),
      options: .atomic
    )
  }

  @MainActor
  private func hierarchyImage<Content: View>(
    _ content: Content
  ) throws -> UIImage {
    let controller = UIHostingController(rootView: content)
    let fittingSize = controller.sizeThatFits(
      in: CGSize(width: 760, height: 10_000)
    )
    guard fittingSize.width > 0, fittingSize.height > 0 else {
      throw SnapshotError.invalidSize
    }

    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    root?.addChild(controller)
    controller.view.frame = CGRect(origin: .zero, size: fittingSize)
    root?.view.addSubview(controller.view)
    controller.didMove(toParent: root)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = true
    let image = UIGraphicsImageRenderer(
      size: fittingSize,
      format: format
    ).image { context in
      controller.view.layer.render(in: context.cgContext)
    }

    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    return image
  }

  private var sample: AyurvedaDisplay {
    AyurvedaDisplay(
      tierLabel: "Classical",
      tierDetail: "from Agathi leaf",
      vata: 2,
      pitta: 0,
      kapha: -2,
      rasa: ["bitter", "sweet"],
      virya: "cooling",
      vipaka: "pungent",
      gunas: ["light", "dry", "rough", "soft"],
      modifierLabels: ["cooked"],
      viruddha: ["Milk and sour fruit are traditionally considered incompatible."],
      contraindications: [
        "Vata excess (strongly bitter–rough).",
        "Pregnancy (traditional caution).",
      ],
      engineExcluded: false,
      edible: true,
      confidence: 0.75,
      qualityCaption: "AI-drafted Ayurvedic details, pending expert review. Informational only — not medical advice.",
      sanskrit: nil
    )
  }
}

private enum SnapshotError: Error {
  case renderFailed(String)
  case invalidSize
}
"""


def run(command, *, capture=False):
    return subprocess.run(
        [str(part) for part in command],
        check=True,
        capture_output=capture,
        text=True,
    )


def simulator_udid(explicit):
    if explicit:
        return explicit
    devices = json.loads(
        run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture=True).stdout
    )
    booted = [
        device["udid"]
        for runtime_devices in devices["devices"].values()
        for device in runtime_devices
        if device["state"] == "Booted"
    ]
    if not booted:
        raise RuntimeError("No booted iOS simulator; pass --device after booting one.")
    return booted[0]


def write_fixture(tmp):
    tmp = Path(tmp)
    app_dir = tmp / "WE3Snapshots.app"
    app_dir.mkdir()
    stubs = tmp / "Stubs.swift"
    main = tmp / "Main.swift"
    stubs.write_text(STUBS)
    main.write_text(APP_SOURCE)

    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleDisplayName": "WE3 Snapshots",
        "CFBundleExecutable": "WE3Snapshots",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "WE3Snapshots",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSRequiresIPhoneOS": True,
        "MinimumOSVersion": "18.0",
        "UIDeviceFamily": [1, 2],
        "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    }
    with (app_dir / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)

    fixture_assets = tmp / "FixtureAssets.xcassets"
    fixture_assets.mkdir()
    (fixture_assets / "Contents.json").write_text(
        '{"info":{"author":"xcode","version":1}}\n'
    )
    assets = ROOT / "Ayura/Assets.xcassets"
    for name in COLOR_ASSETS:
        shutil.copytree(assets / name, fixture_assets / name)

    sdk = run(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
        capture=True,
    ).stdout.strip()
    run(
        [
            "xcrun",
            "swiftc",
            "-parse-as-library",
            "-sdk",
            sdk,
            "-target",
            "arm64-apple-ios18.0-simulator",
            "-framework",
            "SwiftUI",
            "-framework",
            "UIKit",
            "-framework",
            "SwiftData",
            *SOURCE_FILES,
            stubs,
            main,
            "-o",
            app_dir / "WE3Snapshots",
        ]
    )
    run(
        [
            "xcrun",
            "actool",
            fixture_assets,
            "--compile",
            app_dir,
            "--output-format",
            "human-readable-text",
            "--platform",
            "iphonesimulator",
            "--minimum-deployment-target",
            "18.0",
            "--target-device",
            "iphone",
            "--target-device",
            "ipad",
        ]
    )
    return app_dir


def png_dimensions(path):
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path} is not a PNG")
    return struct.unpack(">II", data[16:24])


def render(device, output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="we3-snapshots-") as tmp:
        app = write_fixture(tmp)
        subprocess.run(
            ["xcrun", "simctl", "uninstall", device, BUNDLE_ID],
            check=False,
            capture_output=True,
            text=True,
        )
        run(["xcrun", "simctl", "install", device, app])
        run(
            [
                "xcrun",
                "simctl",
                "launch",
                "--terminate-running-process",
                device,
                BUNDLE_ID,
            ]
        )
        data_container = Path(
            run(
                [
                    "xcrun",
                    "simctl",
                    "get_app_container",
                    device,
                    BUNDLE_ID,
                    "data",
                ],
                capture=True,
            ).stdout.strip()
        )
        documents = data_container / "Documents"
        done = documents / "WE3-SNAPSHOTS-DONE"
        for _ in range(120):
            if done.exists():
                break
            time.sleep(0.25)
        else:
            raise RuntimeError("Timed out waiting for WE-3 snapshot renderer.")

        for name in SNAPSHOT_NAMES:
            source = documents / name
            if not source.exists():
                raise RuntimeError(f"Renderer did not create {name}.")
            shutil.copy2(source, output / name)


def verify_snapshots(rendered, baselines):
    rendered = Path(rendered)
    baselines = Path(baselines)
    dimensions = {}
    comparisons = {}
    for name in SNAPSHOT_NAMES:
        actual = rendered / name
        expected = baselines / name
        if not expected.exists():
            raise AssertionError(f"Missing baseline {expected}; run with --record.")
        dimensions[name] = png_dimensions(actual)
        expected_dimensions = png_dimensions(expected)
        if dimensions[name] != expected_dimensions:
            raise AssertionError(
                f"Snapshot dimensions differ: {name} "
                f"(actual={dimensions[name]}, expected={expected_dimensions})"
            )

        with Image.open(actual) as actual_image, Image.open(expected) as expected_image:
            difference = ImageChops.difference(
                actual_image.convert("RGBA"),
                expected_image.convert("RGBA"),
            )
            statistics = ImageStat.Stat(difference)
            mean = max(statistics.mean[:3])
            rms = max(statistics.rms[:3])
            comparisons[name] = (mean, rms)
            if mean > 1.0 or rms > 8.0:
                raise AssertionError(
                    f"Snapshot differs: {name} "
                    f"(max-channel mean={mean:.3f}, RMS={rms:.3f})"
                )

    default_height = dimensions["ayurveda-light-default.png"][1]
    largest_height = dimensions["ayurveda-light-accessibility5.png"][1]
    if largest_height <= default_height:
        raise AssertionError(
            "Accessibility-5 snapshot did not expand vertically; "
            "possible clipping or Dynamic Type regression."
        )
    if len({width for width, _ in dimensions.values()}) != 1:
        raise AssertionError("Snapshot widths differ across variants.")
    return dimensions, comparisons


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", help="Booted simulator UDID")
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    device = simulator_udid(args.device)
    with tempfile.TemporaryDirectory(prefix="we3-rendered-") as rendered:
        render(device, rendered)
        if args.record:
            BASELINES.mkdir(parents=True, exist_ok=True)
            for name in SNAPSHOT_NAMES:
                shutil.copy2(Path(rendered) / name, BASELINES / name)
        dimensions, comparisons = verify_snapshots(rendered, BASELINES)
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for name in SNAPSHOT_NAMES:
                shutil.copy2(Path(rendered) / name, args.output / name)

    for name in SNAPSHOT_NAMES:
        width, height = dimensions[name]
        mean, rms = comparisons[name]
        print(
            f"PASS {name}: {width}x{height}; "
            f"max-channel mean={mean:.3f}, RMS={rms:.3f}"
        )


if __name__ == "__main__":
    main()
