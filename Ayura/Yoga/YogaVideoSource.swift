import AVFoundation
import UIKit

/// Random-access yoga imagery keyed only by ExerciseItem's stable UUID.
/// Numeric catalogue provenance, display names, Sanskrit names, slugs and
/// asset filenames never participate in runtime frame selection.
final class YogaVideoSource: @unchecked Sendable {
    static let shared = YogaVideoSource()

    private static let framesPerSecond: Int64 = 30
    private static let mediaTimescale: CMTimeScale = 600
    private static let expectedFrameCount = 908
    private static let expectedArchiveByteCounts: [String: Int64] = [
        "144": 3_292_621,
        "480": 13_614_817,
        "1024": 47_000_394,
    ]

    private let stateLock = NSLock()
    private let decodeLock = NSLock()
    private var generators: [String: AVAssetImageGenerator] = [:]
    private var frameIndex: [UUID: Int] = [:]
    private var timestampCount = 0

    func hasVideo(for asanaID: UUID) -> Bool {
        frameIndex[asanaID] != nil
    }

    var availableAsanaIDs: [UUID] {
        frameIndex.keys.sorted { $0.uuidString < $1.uuidString }
    }

    private init() {
        if let url = Bundle.main.url(
            forResource: "frame_timestamps",
            withExtension: "json",
            subdirectory: "Yoga"
        ),
           let data = try? Data(contentsOf: url),
           let timestamps = try? JSONDecoder().decode([Double].self, from: data) {
            // Validation-only artifact; lookup uses exact integer ticks.
            timestampCount = timestamps.count
        } else {
            print("❌ Error: Yoga/frame_timestamps.json missing or invalid!")
        }
        guard timestampCount == Self.expectedFrameCount else {
            print(
                "❌ Error: Yoga/frame_timestamps.json has \(timestampCount) entries; "
                    + "expected \(Self.expectedFrameCount)!"
            )
            timestampCount = 0
            return
        }

        if let url = Bundle.main.url(
            forResource: "frame_index",
            withExtension: "json",
            subdirectory: "Yoga"
        ),
           let data = try? Data(contentsOf: url),
           let raw = try? JSONDecoder().decode([String: Int].self, from: data) {
            let pairs = raw.compactMap { key, value -> (UUID, Int)? in
                guard let asanaID = UUID(uuidString: key) else { return nil }
                return (asanaID, value)
            }
            guard pairs.count == raw.count else {
                print("❌ Error: Yoga/frame_index.json contains a non-UUID asana id!")
                return
            }
            frameIndex = Dictionary(uniqueKeysWithValues: pairs)
        } else {
            print("❌ Error: Yoga/frame_index.json missing or invalid!")
        }

        let expectedFrames = Set(0..<Self.expectedFrameCount)
        guard frameIndex.count == Self.expectedFrameCount,
              Set(frameIndex.values) == expectedFrames else {
            print(
                "❌ Error: Yoga/frame_index.json is not the expected "
                    + "\(Self.expectedFrameCount)-entry ID/frame bijection!"
            )
            frameIndex = [:]
            return
        }
    }

    private func generator(for variant: String) -> AVAssetImageGenerator? {
        stateLock.lock()
        if let existing = generators[variant] {
            stateLock.unlock()
            return existing
        }
        stateLock.unlock()

        guard let expectedByteCount = Self.expectedArchiveByteCounts[variant] else {
            print("❌ Error: unsupported yoga archive variant \(variant)!")
            return nil
        }
        let resourceName = "yoga_archive_\(variant)"
        guard let videoURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "mp4",
            subdirectory: "Yoga"
        ) else {
            print("❌ Error: Yoga/\(resourceName).mp4 missing from Bundle!")
            return nil
        }
        let actualByteCount = (
            try? videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        ).map(Int64.init) ?? -1
        guard actualByteCount == expectedByteCount else {
            print(
                "❌ Error: Yoga/\(resourceName).mp4 is \(actualByteCount) bytes; "
                    + "expected \(expectedByteCount)!"
            )
            return nil
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        if let side = Double(variant) {
            generator.maximumSize = CGSize(width: side, height: side)
        }
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        stateLock.lock()
        defer { stateLock.unlock() }
        if let existing = generators[variant] {
            return existing
        }
        generators[variant] = generator
        return generator
    }

    func getFrame(id asanaID: UUID, variant: String) -> UIImage? {
        guard let index = frameIndex[asanaID] else { return nil }
        guard index >= 0, index < timestampCount else {
            print("❌ Frame index \(index) for asana id \(asanaID) is out of bounds")
            return nil
        }
        guard let generator = generator(for: variant) else { return nil }

        let time = FrameArchiveClock.time(
            forFrameIndex: index,
            framesPerSecond: Self.framesPerSecond,
            timescale: Self.mediaTimescale
        )
        decodeLock.lock()
        defer { decodeLock.unlock() }
        do {
            return UIImage(cgImage: try generator.copyCGImage(at: time, actualTime: nil))
        } catch {
            print(
                "❌ Failed to extract image for asana id \(asanaID), frame \(index): "
                    + error.localizedDescription
            )
            return nil
        }
    }
}
