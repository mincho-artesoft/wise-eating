import Foundation
import Compression

struct OptimizedInvisibleCoder {

    // 1. 16‑glyph alphabet – safe BMP invisibles (no VS or Tag chars) ─────
    private static let alphabet: [UnicodeScalar] = [
        "\u{200B}", // 0  ZERO WIDTH SPACE
        "\u{200C}", // 1  ZERO WIDTH NON‑JOINER
        "\u{200D}", // 2  ZERO WIDTH JOINER
        "\u{2060}", // 3  WORD JOINER
        "\u{2061}", // 4  FUNCTION APPLICATION
        "\u{2062}", // 5  INVISIBLE TIMES
        "\u{2063}", // 6  INVISIBLE SEPARATOR
        "\u{2064}", // 7  INVISIBLE PLUS
        "\u{2066}", // 8  LEFT‑TO‑RIGHT ISOLATE
        "\u{2067}", // 9  RIGHT‑TO‑LEFT ISOLATE
        "\u{2068}", // 10 FIRST STRONG ISOLATE
        "\u{2069}", // 11 POP DIRECTIONAL ISOLATE
        "\u{200E}", // 12 LEFT‑TO‑RIGHT MARK
        "\u{200F}", // 13 RIGHT‑TO‑LEFT MARK
        "\u{202A}", // 14 LEFT‑TO‑RIGHT EMBEDDING
        "\u{202B}"  // 15 RIGHT‑TO‑LEFT EMBEDDING
    ].flatMap { $0.unicodeScalars }

    // 2. Reverse map  (scalar → byte)  ──────────────────────────────────── BASE-16
    private static let reverseAlphabet: [UnicodeScalar: UInt8] = {
        var map: [UnicodeScalar: UInt8] = [:]
        for (i, s) in alphabet.enumerated() { map[s] = UInt8(i) }
        return map
    }()

    // 3. ENCODE  (2 glyphs per byte – base‑16)
    static func encode(from text: String) -> String? {
        guard let src = text.data(using: .utf8),
              let deflated = try? compress(data: src) else { return nil }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(deflated.count * 2)
        for byte in deflated {
            scalars.append(alphabet[Int(byte >> 4)])      // high nibble
            scalars.append(alphabet[Int(byte & 0x0F)])    // low  nibble
        }
        return String(scalars)
    }

    // 4. DECODE  (2 glyphs per byte – base‑16)
    static func decode(from invisible: String) -> String? {
        let scalarCount = invisible.unicodeScalars.count
        guard scalarCount > 0, scalarCount % 2 == 0 else { return nil }

        var data = Data(); data.reserveCapacity(scalarCount / 2)
        var iterator = invisible.unicodeScalars.makeIterator()
        while let s1 = iterator.next(), let s2 = iterator.next() {
            guard let hi = reverseAlphabet[s1],
                  let lo = reverseAlphabet[s2] else { return nil }
            data.append((hi << 4) | lo)
        }

        guard let inflated = try? decompress(data: data) else { return nil }
        return String(data: inflated, encoding: .utf8)
    }
    
    // MARK: - Correct Low-Level Compression/Decompression
    
    private static func compress(data: Data) throws -> Data {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        var stream = streamPtr.pointee

        var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.failedToInit }

        var resultData = Data()
        let destinationBufferSize = 4096
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) in
            stream.src_ptr = sourcePtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            stream.src_size = data.count

            while true {
                // Determine the correct flags for this pass.
                // If there's no more source data, we must FINALIZE.
                let flags = (stream.src_size == 0) ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
                
                status = compression_stream_process(&stream, flags)
                
                let count = destinationBufferSize - stream.dst_size
                if count > 0 {
                    resultData.append(destinationBuffer, count: count)
                }

                if status == COMPRESSION_STATUS_END || status == COMPRESSION_STATUS_ERROR {
                    break // Exit loop if stream ended or an error occurred
                }
            }
        }
        
        guard status == COMPRESSION_STATUS_END else { throw CompressionError.processingError }
        status = compression_stream_destroy(&stream)
        guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.failedToDestroy }
        
        return resultData
    }
    
    private static func decompress(data: Data) throws -> Data {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        var stream = streamPtr.pointee

        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.failedToInit }

        var resultData = Data()
        let destinationBufferSize = 4096
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }

        data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) in
            stream.src_ptr = sourcePtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            stream.src_size = data.count

            while true {
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize
                
                status = compression_stream_process(&stream, 0) // No flags needed for decode
                
                let count = destinationBufferSize - stream.dst_size
                if count > 0 {
                    resultData.append(destinationBuffer, count: count)
                }

                if status == COMPRESSION_STATUS_END || status == COMPRESSION_STATUS_ERROR {
                    break
                }
            }
        }
        
        guard status == COMPRESSION_STATUS_END else { throw CompressionError.processingError }
        status = compression_stream_destroy(&stream)
        guard status != COMPRESSION_STATUS_ERROR else { throw CompressionError.failedToDestroy }
        
        return resultData
    }
    
    enum CompressionError: Error {
        case failedToInit
        case processingError
        case failedToDestroy
    }
}
