import Foundation

enum BundledJSONResourceError: Error, LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "Missing bundled JSON resource: \(name).json.gz"
        }
    }
}

/// Loads JSON resources from their compressed bundle representation while
/// retaining a plain JSON fallback for tests and development bundles.
enum BundledJSONResource {
    static func data(
        named name: String,
        bundle: Bundle = .main
    ) throws -> Data {
        if let compressedURL = bundle.url(
            forResource: name,
            withExtension: "json.gz"
        ) {
            let compressed = try Data(
                contentsOf: compressedURL,
                options: .mappedIfSafe
            )
            return try ZlibGzip.decompress(data: compressed)
        }

        if let plainURL = bundle.url(
            forResource: name,
            withExtension: "json"
        ) {
            return try Data(contentsOf: plainURL, options: .mappedIfSafe)
        }

        throw BundledJSONResourceError.missing(name)
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        named name: String,
        bundle: Bundle = .main,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(
            type,
            from: data(named: name, bundle: bundle)
        )
    }
}
