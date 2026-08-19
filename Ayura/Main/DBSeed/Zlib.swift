import Foundation
import zlib

enum ZlibError: Error, LocalizedError {
    case deflateInit(code: Int32)
    case inflateInit(code: Int32)
    case deflate(code: Int32)
    case inflate(code: Int32)
    case unknown

    var errorDescription: String? {
        switch self {
        case .deflateInit(let c): return "deflateInit failed (\(c))"
        case .inflateInit(let c): return "inflateInit failed (\(c))"
        case .deflate(let c):     return "deflate failed (\(c))"
        case .inflate(let c):     return "inflate failed (\(c))"
        case .unknown:            return "Unknown zlib error"
        }
    }
}

/// GZIP container (DEFLATE) using zlib streaming APIs.
enum ZlibGzip {
    static func decompressFile(from sourceURL: URL, to destinationURL: URL) throws {
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree = nil
        stream.opaque = nil

        let initCode = inflateInit2_(
            &stream,
            15 + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initCode == Z_OK else {
            throw ZlibError.inflateInit(code: initCode)
        }
        defer { inflateEnd(&stream) }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw ZlibError.unknown
        }

        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }

        let inputChunkSize = 1_048_576
        let outputChunkSize = 1_048_576
        var reachedStreamEnd = false

        while let inputData = try input.read(upToCount: inputChunkSize),
              !inputData.isEmpty {
            try inputData.withUnsafeBytes { rawInput in
                guard let baseAddress = rawInput
                    .bindMemory(to: Bytef.self).baseAddress else {
                    throw ZlibError.unknown
                }
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: baseAddress
                )
                stream.avail_in = uInt(inputData.count)

                while stream.avail_in > 0, !reachedStreamEnd {
                    var outputBuffer = [UInt8](
                        repeating: 0,
                        count: outputChunkSize
                    )
                    let code = outputBuffer.withUnsafeMutableBytes { rawOutput in
                        stream.next_out = rawOutput
                            .bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(outputChunkSize)
                        return inflate(&stream, Z_NO_FLUSH)
                    }

                    let produced = outputChunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        try output.write(
                            contentsOf: Data(outputBuffer.prefix(produced))
                        )
                    }

                    switch code {
                    case Z_STREAM_END:
                        reachedStreamEnd = true
                    case Z_OK:
                        break
                    default:
                        throw ZlibError.inflate(code: code)
                    }
                }
            }
            if reachedStreamEnd { break }
        }

        guard reachedStreamEnd else {
            throw ZlibError.inflate(code: Z_DATA_ERROR)
        }
    }

    static func compress(data: Data, level: Int32 = Z_DEFAULT_COMPRESSION) throws -> Data {
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree  = nil
        stream.opaque = nil

        let initCode = deflateInit2_(
            &stream,
            level,
            Z_DEFLATED,
            15 + 16, // gzip container
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initCode == Z_OK else { throw ZlibError.deflateInit(code: initCode) }
        defer { deflateEnd(&stream) }

        var output = Data()
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcBase = src.bindMemory(to: Bytef.self).baseAddress else { throw ZlibError.unknown }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
            stream.avail_in = uInt(data.count)

            let chunkSize = 64 * 1024
            var outBuffer = [UInt8](repeating: 0, count: chunkSize)

            while stream.avail_in > 0 {
                outBuffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                }
                let code = deflate(&stream, Z_NO_FLUSH)
                if code != Z_OK && code != Z_STREAM_END && code != Z_BUF_ERROR {
                    throw ZlibError.deflate(code: code)
                }
                let have = chunkSize - Int(stream.avail_out)
                if have > 0 { output.append(&outBuffer, count: have) }
            }

            var finished = false
            while !finished {
                outBuffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                }
                let code = deflate(&stream, Z_FINISH)
                switch code {
                case Z_STREAM_END: finished = true
                case Z_OK, Z_BUF_ERROR: break
                default: throw ZlibError.deflate(code: code)
                }
                let have = chunkSize - Int(stream.avail_out)
                if have > 0 { output.append(&outBuffer, count: have) }
            }
        }
        return output
    }

    static func decompress(data: Data) throws -> Data {
        var stream = z_stream()
        stream.zalloc = nil
        stream.zfree  = nil
        stream.opaque = nil

        let initCode = inflateInit2_(
            &stream,
            15 + 32, // auto-detect gzip/zlib
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initCode == Z_OK else { throw ZlibError.inflateInit(code: initCode) }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: max(64 * 1024, data.count * 2))
        try data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            guard let srcBase = src.bindMemory(to: Bytef.self).baseAddress else { throw ZlibError.unknown }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
            stream.avail_in = uInt(data.count)

            let chunkSize = 64 * 1024
            var outBuffer = [UInt8](repeating: 0, count: chunkSize)

            var done = false
            while !done {
                outBuffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                }
                let code = inflate(&stream, Z_NO_FLUSH)
                switch code {
                case Z_STREAM_END: done = true
                case Z_OK: break
                case Z_BUF_ERROR: break
                default: throw ZlibError.inflate(code: code)
                }

                let have = chunkSize - Int(stream.avail_out)
                if have > 0 { output.append(&outBuffer, count: have) }

                if stream.avail_in == 0 && stream.avail_out == uInt(chunkSize) && code == Z_BUF_ERROR {
                    break // no more progress possible
                }
            }
        }
        return output
    }
}
