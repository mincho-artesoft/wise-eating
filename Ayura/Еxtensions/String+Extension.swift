import Foundation

extension String {
    
    // MARK: - Normalization Helpers
    
    func nilIfEmpty() -> String? {
        return self.isEmpty ? nil : self
    }
    
    func ifEmpty(_ replacement: String) -> String {
        return self.isEmpty ? replacement : self
    }
    
    /// Used by Search to generate folded search keys
    var foldedSearchKey: String {
        return self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
    
    var _normKey: String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    // MARK: - Asset Key Helpers (Required by ExerciseItem)
    
    /// Strict variant: replaces non-alphanumeric chars with "_"
    /// e.g. "A, b" -> "A__b"
    func assetKeyStrict() -> String {
        return self.unicodeScalars.map { scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                return String(scalar)
            } else {
                return "_"
            }
        }.joined()
    }

    /// Collapsed variant: replaces non-alphanumeric with "_", then collapses sequence of "_"
    func assetKeyCollapsed() -> String {
        let replaced = self.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()

        // Collapse sequences of "_"
        let collapsed = replaced.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        // Trim leading/trailing "_"
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
    
    // MARK: - Levenshtein Distance
    
    func levenshteinDistance(to destination: String) -> Int {
        let s = Array(self)
        let t = Array(destination)
        let sCount = s.count
        let tCount = t.count
        
        if sCount == 0 { return tCount }
        if tCount == 0 { return sCount }
        
        var v0 = Array(0...tCount)
        var v1 = [Int](repeating: 0, count: tCount + 1)
        
        for i in 0..<sCount {
            v1[0] = i + 1
            for j in 0..<tCount {
                let cost = (s[i] == t[j]) ? 0 : 1
                v1[j + 1] = Swift.min(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost)
            }
            for j in 0...tCount { v0[j] = v1[j] }
        }
        
        return v1[tCount]
    }
}
