import AVFoundation
import UIKit

/// Random-access food imagery keyed only by the database FoodItem id.
///
/// Human-readable names remain build-time provenance in foods_index.csv. They
/// are intentionally absent from this runtime path: renaming a food must not
/// detach it from its frame or attach another food's picture.
final class FoodVideoSource: @unchecked Sendable {
    static let shared = FoodVideoSource()

    private let stateLock = NSLock()
    private let decodeLock = NSLock()
    private var generators: [String: AVAssetImageGenerator] = [:]
    private var frameIndex: [UUID: Int] = [:]
    private var timestamps: [Double] = []

    func hasVideo(for foodID: UUID) -> Bool {
        frameIndex[foodID] != nil
    }

    var availableFoodIDs: [UUID] {
        frameIndex.keys.sorted { $0.uuidString < $1.uuidString }
    }

    private init() {
        if let url = Bundle.main.url(
            forResource: "frame_timestamps",
            withExtension: "json"
        ),
           let data = try? Data(contentsOf: url),
           let times = try? JSONDecoder().decode([Double].self, from: data) {
            timestamps = times
        } else {
            print("❌ Error: frame_timestamps.json missing or invalid!")
        }

        if let url = Bundle.main.url(forResource: "frame_index", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: Int].self, from: data) {
            let pairs = raw.compactMap { key, value -> (UUID, Int)? in
                guard let foodID = UUID(uuidString: key) else { return nil }
                return (foodID, value)
            }
            guard pairs.count == raw.count else {
                print("❌ Error: frame_index.json contains a non-UUID DB id!")
                return
            }
            frameIndex = Dictionary(uniqueKeysWithValues: pairs)
        } else {
            print("❌ Error: frame_index.json missing or invalid!")
        }

        if let maximumIndex = frameIndex.values.max(), maximumIndex >= timestamps.count {
            print(
                "❌ Error: frame_index.json references frame \(maximumIndex), "
                + "but only \(timestamps.count) timestamps are bundled!"
            )
            frameIndex = [:]
        }
    }

    private func generator(for variant: String) -> AVAssetImageGenerator? {
        stateLock.lock()
        if let existing = generators[variant] {
            stateLock.unlock()
            return existing
        }
        stateLock.unlock()

        let resourceName = "food_archive_\(variant)"
        guard let videoURL = BundledLargeAssetLoader.url(
            forResource: resourceName,
            withExtension: "mp4"
        ) else {
            print("❌ Error: \(resourceName).mp4 missing from Bundle! Check Target Membership.")
            return nil
        }

        let asset = AVURLAsset(url: videoURL)
        let created = AVAssetImageGenerator(asset: asset)
        created.appliesPreferredTrackTransform = true
        if let side = Double(variant) {
            created.maximumSize = CGSize(width: side, height: side)
        } else {
            created.maximumSize = CGSize(width: 1024, height: 1024)
        }
        created.requestedTimeToleranceBefore = .zero
        created.requestedTimeToleranceAfter = .zero

        stateLock.lock()
        defer { stateLock.unlock() }
        if let existing = generators[variant] {
            return existing
        }
        generators[variant] = created
        return created
    }

    func getFrame(id foodID: UUID, variant: String) -> UIImage? {
        guard let index = frameIndex[foodID] else { return nil }
        guard index >= 0, index < timestamps.count else {
            print("❌ Frame index \(index) for food id \(foodID) is out of bounds")
            return nil
        }
        guard let generator = generator(for: variant) else { return nil }

        // Exact 30 fps positions on a 600 Hz media clock. Never add the old
        // +0.01 s nudge and never loosen the tolerance: both return neighbours.
        let time = CMTime(seconds: timestamps[index], preferredTimescale: 600)
        decodeLock.lock()
        defer { decodeLock.unlock() }
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print(
                "❌ Failed to extract image for food id \(foodID), frame \(index): "
                + error.localizedDescription
            )
            return nil
        }
    }
}
