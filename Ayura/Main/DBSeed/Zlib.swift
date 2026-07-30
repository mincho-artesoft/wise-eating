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
