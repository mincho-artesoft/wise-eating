import Foundation
import zlib

enum BundledLargeAssetLoader {
    private struct AssetDescriptor {
        let outputFileName: String
        let archiveResourceName: String
        let partSuffixes: [String]
        let expectedByteCount: Int64
        let contentVersion: String
    }

    private enum AssetError: Error, LocalizedError {
        case missingPart(String)
        case cannotCreateOutput(URL)
        case inflateInitializationFailed(Int32)
        case inflateFailed(Int32)
        case truncatedArchive
        case trailingArchiveData
        case unexpectedSize(expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case .missingPart(let name):
                return "Missing bundled archive part: \(name)"
            case .cannotCreateOutput(let url):
                return "Could not create extracted asset at \(url.path)"
            case .inflateInitializationFailed(let code):
                return "Could not initialize gzip decompression (\(code))"
            case .inflateFailed(let code):
                return "Gzip decompression failed (\(code))"
            case .truncatedArchive:
                return "The bundled gzip archive is incomplete"
            case .trailingArchiveData:
                return "The bundled gzip archive contains unexpected trailing data"
            case .unexpectedSize(let expected, let actual):
                return "Extracted asset size mismatch (expected \(expected), found \(actual))"
            }
        }
    }

    private static let foodArchive1024 = AssetDescriptor(
        outputFileName: "food_archive_1024.mp4",
        archiveResourceName: "food_archive_1024.mp4.gz",
        partSuffixes: ["aa", "ab", "ac", "ad", "ae"],
        expectedByteCount: 352_217_385,
        contentVersion: "8bc992c8e036eecb8a02c9157ef3b92e0c7adacf63dca2aca2fe9c2be627a969"
    )

    private static let preparationLock = NSLock()

    /// Starts preparing large bundled assets during app launch.
    ///
    /// Extraction is idempotent: a successfully restored asset is reused on
    /// later launches until its content version changes.
    static func prepareBundledAssets() {
        do {
            _ = try prepare(foodArchive1024)
            print("✅ Large bundled assets are ready.")
        } catch {
            print("❌ Failed to prepare large bundled assets: \(error.localizedDescription)")
        }
    }

    /// Resolves regular bundle resources and transparently restores split large assets.
    static func url(forResource resourceName: String, withExtension extensionName: String) -> URL? {
        if let bundledURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: extensionName
        ) {
            return bundledURL
        }

        guard resourceName == "food_archive_1024", extensionName == "mp4" else {
            return nil
        }

        do {
            return try prepare(foodArchive1024)
        } catch {
            print("❌ Failed to restore \(resourceName).\(extensionName): \(error.localizedDescription)")
            return nil
        }
    }

    private static func prepare(_ asset: AssetDescriptor) throws -> URL {
        preparationLock.lock()
        defer { preparationLock.unlock() }

        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var assetDirectory = applicationSupportURL.appendingPathComponent(
            "LargeAssets",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: assetDirectory,
            withIntermediateDirectories: true
        )

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? assetDirectory.setResourceValues(resourceValues)

        let destinationURL = assetDirectory.appendingPathComponent(asset.outputFileName)
        let versionURL = assetDirectory.appendingPathComponent(
            "\(asset.outputFileName).version"
        )

        if isCurrent(
            destinationURL: destinationURL,
            versionURL: versionURL,
            asset: asset,
            fileManager: fileManager
        ) {
            return destinationURL
        }

        let partURLs = try asset.partSuffixes.map { suffix in
            let extensionName = "part-\(suffix)"
            guard let url = Bundle.main.url(
                forResource: asset.archiveResourceName,
                withExtension: extensionName
            ) else {
                throw AssetError.missingPart(
                    "\(asset.archiveResourceName).\(extensionName)"
                )
            }
            return url
        }

        let temporaryURL = assetDirectory.appendingPathComponent(
            "\(asset.outputFileName).extracting"
        )
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }

        do {
            try inflate(partURLs: partURLs, to: temporaryURL)

            let attributes = try fileManager.attributesOfItem(atPath: temporaryURL.path)
            let actualByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard actualByteCount == asset.expectedByteCount else {
                throw AssetError.unexpectedSize(
                    expected: asset.expectedByteCount,
                    actual: actualByteCount
                )
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try Data(asset.contentVersion.utf8).write(to: versionURL, options: .atomic)
            return destinationURL
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }

    private static func isCurrent(
        destinationURL: URL,
        versionURL: URL,
        asset: AssetDescriptor,
        fileManager: FileManager
    ) -> Bool {
        guard
            fileManager.fileExists(atPath: destinationURL.path),
            let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value,
            byteCount == asset.expectedByteCount,
            let versionData = try? Data(contentsOf: versionURL),
            String(decoding: versionData, as: UTF8.self) == asset.contentVersion
        else {
            return false
        }
        return true
    }

    private static func inflate(partURLs: [URL], to outputURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw AssetError.cannotCreateOutput(outputURL)
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let initializationCode = inflateInit2_(
            &stream,
            15 + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initializationCode == Z_OK else {
            throw AssetError.inflateInitializationFailed(initializationCode)
        }
        defer { inflateEnd(&stream) }

        let inputChunkSize = 1_048_576
        let outputChunkSize = 1_048_576
        var outputBuffer = [UInt8](repeating: 0, count: outputChunkSize)
        var reachedStreamEnd = false

        for partURL in partURLs {
            let inputHandle = try FileHandle(forReadingFrom: partURL)
            defer { try? inputHandle.close() }

            while let inputData = try inputHandle.read(upToCount: inputChunkSize),
                  !inputData.isEmpty {
                if reachedStreamEnd {
                    throw AssetError.trailingArchiveData
                }

                try inputData.withUnsafeBytes { inputBytes in
                    guard let inputBaseAddress = inputBytes
                        .bindMemory(to: Bytef.self)
                        .baseAddress else {
                        return
                    }

                    stream.next_in = UnsafeMutablePointer<Bytef>(
                        mutating: inputBaseAddress
                    )
                    stream.avail_in = uInt(inputData.count)

                    while stream.avail_in > 0 {
                        let result: (code: Int32, produced: Int) =
                            outputBuffer.withUnsafeMutableBytes { outputBytes in
                                stream.next_out = outputBytes
                                    .bindMemory(to: Bytef.self)
                                    .baseAddress
                                stream.avail_out = uInt(outputChunkSize)
                                let code = zlib.inflate(&stream, Z_NO_FLUSH)
                                let produced = outputChunkSize - Int(stream.avail_out)
                                return (code, produced)
                            }

                        if result.produced > 0 {
                            try outputHandle.write(
                                contentsOf: Data(outputBuffer[0..<result.produced])
                            )
                        }

                        switch result.code {
                        case Z_STREAM_END:
                            reachedStreamEnd = true
                            if stream.avail_in > 0 {
                                throw AssetError.trailingArchiveData
                            }
                        case Z_OK:
                            break
                        default:
                            throw AssetError.inflateFailed(result.code)
                        }
                    }
                }
            }
        }

        guard reachedStreamEnd else {
            throw AssetError.truncatedArchive
        }
        try outputHandle.synchronize()
    }
}
