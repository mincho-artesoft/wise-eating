import Foundation

extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard
            let data = rawValue.data(using: .utf8),
            let array = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = array
    }
    
    public var rawValue: String {
        guard
            let data = try? JSONEncoder().encode(self),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return jsonString
    }
    
    func rotated(by offset: Int) -> [Element] {
        guard !isEmpty else { return self }
        let o = ((offset % count) + count) % count
        return Array(self[o...] + self[..<o])
    }
}

extension Array where Element == String {
    func uniqued(caseInsensitive: Bool = false) -> [String] {
        var seen = Set<String>()
        return self.filter { s in
            let key = caseInsensitive ? s.lowercased() : s
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
    func containsCI(_ s: String) -> Bool {
        self.contains { $0.caseInsensitiveCompare(s) == .orderedSame }
    }
}

extension Array where Element == String {
    func dedupCaseInsensitive() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(self.count)
        for s in self {
            let key = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(s)
        }
        return out
    }
}
