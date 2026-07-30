import Foundation

enum PreseedLoader {
    enum PreseedError: Error { case missingBundleResources, combineFailed }

    /// Prepare the pre-seeded SwiftData store by combining split gzip parts (if present),
    /// then gunzipping to a temporary `.store` file and copying it to `storeURL`.
    static func preparePreseededStore(to storeURL: URL) throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory

        // 1) Prefer 3-part split: preseeded_db.store.gz.part-aa/ab/ac
        let partSuffixes = ["aa","ab"]
        let partURLs: [URL] = partSuffixes.compactMap { suffix in
            Bundle.main.url(forResource: "preseeded_db.store.gz", withExtension: "part-\(suffix)")
        }

        var gzURL: URL?
        var combinedURL: URL?

        if partURLs.count == partSuffixes.count {
            let combinedGZ = tmpDir.appendingPathComponent("preseeded_db.store.gz")
            // Remove if exists from a previous attempt
            try? fm.removeItem(at: combinedGZ)
            guard fm.createFile(atPath: combinedGZ.path, contents: nil) else {
                throw PreseedError.combineFailed
            }
            // Stream-append each part (1MB chunks)
            let outHandle = try FileHandle(forWritingTo: combinedGZ)
            defer { try? outHandle.close() }
            for p in partURLs { // keep declared order aa -> ab -> ac
                let inHandle = try FileHandle(forReadingFrom: p)
                defer { try? inHandle.close() }
                while true {
                    let chunk = try inHandle.read(upToCount: 1_048_576) // 1 MB
                    guard let data = chunk, !data.isEmpty else { break }
                    try outHandle.seekToEnd()
                    outHandle.write(data)
                }
            }
            gzURL = combinedGZ
            combinedURL = combinedGZ
        }

        // 2) Fallback to a single .gz in bundle
        if gzURL == nil {
            gzURL = Bundle.main.url(forResource: "preseeded_db", withExtension: "store.gz")
        }

        // 3) Fallback to a plain .store in bundle (legacy path)
        let plainStoreURL = Bundle.main.url(forResource: "preseeded_db", withExtension: "store")

        if let gzURL {
            // Decompress the gzip file using existing ZlibGzip utility.
            let gzData = try Data(contentsOf: gzURL, options: .mappedIfSafe)
            let decompressed = try ZlibGzip.decompress(data: gzData)
            let tmpStore = tmpDir.appendingPathComponent("preseeded_db.store")
            try? fm.removeItem(at: tmpStore)
            try decompressed.write(to: tmpStore, options: .atomic)

            // Ensure destination directory exists
            try fm.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Remove any existing files at destination (store, wal, shm will be handled by caller)
            if fm.fileExists(atPath: storeURL.path) { try fm.removeItem(at: storeURL) }
            try fm.copyItem(at: tmpStore, to: storeURL)

            // Cleanup combined .gz temp if we created it
            if let combinedURL { try? fm.removeItem(at: combinedURL) }
            try? fm.removeItem(at: tmpStore)
            return
        }

        // If we have a plain .store, copy it as-is
        if let plain = plainStoreURL {
            try fm.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: storeURL.path) { try fm.removeItem(at: storeURL) }
            try fm.copyItem(at: plain, to: storeURL)
            return
        }

        throw PreseedError.missingBundleResources
    }
}
