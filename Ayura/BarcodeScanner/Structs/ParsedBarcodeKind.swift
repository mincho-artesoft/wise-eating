import Foundation

public enum ParsedBarcodeKind: String, Sendable {
    case url = "URL"
    case wifi = "Wi-Fi"
    case json = "JSON"
    case gtin = "GTIN / EAN / UPC" // Product code
    case gs1 = "GS1"
    case text = "Text"
}

public struct ParsedBarcode: Sendable {
    public let kind: ParsedBarcodeKind
    public let summary: String
    public let urlToOpen: URL?
    public let prettyJSON: String?
    public let extras: [String:String]
}

public enum BarcodeParser {
    public static func parse(_ raw: String) -> ParsedBarcode {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let u = URL(string: s), ["http","https"].contains(u.scheme?.lowercased() ?? "") {
            return .init(kind: .url, summary: u.host ?? u.absoluteString, urlToOpen: u, prettyJSON: nil, extras: [:])
        }

        if let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data), let pretty = prettyJSON(obj) {
            return .init(kind: .json, summary: "Valid JSON (\(data.count) B)", urlToOpen: nil, prettyJSON: pretty, extras: [:])
        }

        if s.lowercased().hasPrefix("wifi:") {
            let dict = parseSemicolonPairs(String(s.dropFirst(5)))
            let ssid = dict["S"] ?? dict["s"] ?? "Unknown"
            var ex: [String:String] = ["ssid": ssid, "auth": dict["T"] ?? dict["t"] ?? "WPA/WPA2?"]
            if let pass = dict["P"] ?? dict["p"] { ex["password"] = pass }
            let sum = "SSID: \(ssid)\(ex["password"] != nil ? ", password: ••••" : "")"
            return .init(kind: .wifi, summary: sum, urlToOpen: nil, prettyJSON: nil, extras: ex)
        }

        if let gs1 = parseGS1(s) {
            return .init(kind: .gs1, summary: gs1.summary, urlToOpen: nil, prettyJSON: nil, extras: gs1.extras)
        }

        if let gtin = normalizeGTIN(s) {
            return .init(kind: .gtin, summary: "GTIN \(gtin)", urlToOpen: nil, prettyJSON: nil, extras: ["gtin": gtin])
        }

        return .init(kind: .text, summary: s, urlToOpen: nil, prettyJSON: nil, extras: [:])
    }

    public static func firstURL(in raw: String) -> URL? {
        parse(raw).urlToOpen
    }

    private static func prettyJSON(_ obj: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func parseSemicolonPairs(_ s: String) -> [String:String] {
        var result: [String:String] = [:]
        for part in s.split(separator: ";") {
            if let idx = part.firstIndex(of: ":") {
                result[String(part[..<idx])] = String(part[part.index(after: idx)...])
            }
        }
        return result
    }

    private static func normalizeGTIN(_ s: String) -> String? {
        let digits = s.filter(\.isNumber)
        guard [8,12,13,14].contains(digits.count) else { return nil }
        // Basic check, for production you might want a full checksum validation.
        return digits
    }

    private static func parseGS1(_ s: String) -> (summary: String, extras: [String:String])? {
        let replaced = s.map { $0.asciiValue == 29 ? ")" : $0 }.map(String.init).joined()
        let tokens = replaced.split(separator: "(").flatMap { $0.split(separator: ")") }
        var dict: [String:String] = [:]
        for t in tokens where !t.isEmpty {
            let ai = String(t.prefix(2))
            let val = String(t.dropFirst(2))
            if ai.allSatisfy(\.isNumber) { dict[ai] = val }
        }
        guard !dict.isEmpty, let gtin = dict["01"] else { return nil }
        let summary = "GTIN \(gtin)" + (dict["17"].map { " Expire \($0)" } ?? "") + (dict["10"].map { " Lot \($0)" } ?? "")
        return (summary, dict)
    }
}
