import AppKit
import AVFoundation
import Foundation

/// Exercise the same exact-timestamp AVAssetImageGenerator path used by the app.
/// This intentionally does not fall back to AVAssetReader or loosen tolerance.
struct Arguments {
    let archive: URL
    let frameIndex: URL
    let timestamps: URL
    let ids: [String]
    let outputDirectory: URL
    let framesPerSecond: Int64
    let mediaTimescale: Int64

    init() throws {
        var values: [String: String] = [:]
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            guard flag.hasPrefix("--"), let value = iterator.next() else {
                throw ValidationError("expected --flag value pairs")
            }
            values[String(flag.dropFirst(2))] = value
        }
        guard let archive = values["archive"],
              let frameIndex = values["frame-index"],
              let timestamps = values["timestamps"],
              let ids = values["ids"],
              let output = values["out"] else {
            throw ValidationError(
                "usage: verify_frame_archive.swift --archive <mp4> "
                    + "--frame-index <json> --timestamps <json> "
                    + "--ids <comma-separated integers> --out <directory>"
            )
        }
        let parsedIDs = ids.split(separator: ",").map(String.init)
        guard !parsedIDs.isEmpty else {
            throw ValidationError("at least one catalogue id is required")
        }
        self.archive = URL(fileURLWithPath: archive)
        self.frameIndex = URL(fileURLWithPath: frameIndex)
        self.timestamps = URL(fileURLWithPath: timestamps)
        self.ids = parsedIDs
        self.outputDirectory = URL(fileURLWithPath: output, isDirectory: true)
        self.framesPerSecond = Int64(values["fps"] ?? "30") ?? 0
        self.mediaTimescale = Int64(values["timescale"] ?? "600") ?? 0
        guard framesPerSecond > 0, mediaTimescale > 0 else {
            throw ValidationError("fps and timescale must be positive integers")
        }
        guard mediaTimescale % framesPerSecond == 0 else {
            throw ValidationError(
                "timescale \(mediaTimescale) does not divide evenly by fps \(framesPerSecond)"
            )
        }
    }
}

struct ValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
enum VerifyFrameArchive {
    static func main() {
        do {
            try run()
        } catch {
            fputs("verify_frame_archive: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
    let arguments = try Arguments()
    let decoder = JSONDecoder()
    let rawIndex = try decoder.decode(
        [String: Int].self,
        from: Data(contentsOf: arguments.frameIndex)
    )
    let timestamps = try decoder.decode(
        [Double].self,
        from: Data(contentsOf: arguments.timestamps)
    )
    try FileManager.default.createDirectory(
        at: arguments.outputDirectory,
        withIntermediateDirectories: true
    )

    let asset = AVURLAsset(url: arguments.archive)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let timescale = CMTimeScale(arguments.mediaTimescale)

    print("id\tframe\trequested_seconds\tactual_seconds\tdelta_seconds\tpng")
    for id in arguments.ids {
        guard let frame = rawIndex[id] else {
            throw ValidationError("catalogue id \(id) has no frame-index entry")
        }
        guard timestamps.indices.contains(frame) else {
            throw ValidationError(
                "catalogue id \(id) points at frame \(frame), outside timestamps"
            )
        }
        let requested = FrameArchiveClock.time(
            forFrameIndex: frame,
            framesPerSecond: arguments.framesPerSecond,
            timescale: timescale
        )
        var actual = CMTime.invalid
        let cgImage = try generator.copyCGImage(at: requested, actualTime: &actual)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ValidationError("could not encode extracted frame for id \(id)")
        }
        let output = arguments.outputDirectory.appendingPathComponent("\(id).png")
        try png.write(to: output, options: .atomic)
        let requestedSeconds = requested.seconds
        let actualSeconds = actual.seconds
        let delta = abs(actualSeconds - requestedSeconds)
        guard delta < 1e-9 else {
            throw ValidationError(
                "id \(id) returned \(actualSeconds), requested \(requestedSeconds)"
            )
        }
        print(
            "\(id)\t\(frame)\t\(requestedSeconds)\t\(actualSeconds)\t"
                + "\(delta)\t\(output.path)"
        )
    }
    }
}
