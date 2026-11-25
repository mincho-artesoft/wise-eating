import Foundation

/// A small in-memory search index over the names of catalogue items, shared by
/// the tabs that do not need the food engine's command language.
///
/// An item answers to several names at once — its English name, its Sanskrit
/// name, its name in the user's language — and to the words of its facets
/// (family, level, muscle groups). All of them are indexed side by side, so
/// "adho mukha", "downward dog" and "куче" reach the same pose, and "standing
/// beginner" narrows by facet. Word order does not matter, a word may be typed
/// only in part, and a word that matches nothing is tried again with one or two
/// typing errors allowed.
struct NameSearchIndex<ID: Hashable & Sendable>: Sendable {
    struct Entry: Sendable {
        let id: ID
        /// Every name the item answers to; the first is used to break ties.
        let names: [String]
        /// Facet labels, searched like names but ranked below them.
        let facets: [String]
    }

    private struct Record: Sendable {
        let id: ID
        let foldedNames: [String]
        let wordCount: Int
        let sortKey: String
    }

    private let records: [Record]
    private let nameWords: [String: [Int]]
    private let facetWords: [String: [Int]]
    private let vocabulary: [String]

    init(_ entries: [Entry]) {
        var records: [Record] = []
        var nameWords: [String: [Int]] = [:]
        var facetWords: [String: [Int]] = [:]
        records.reserveCapacity(entries.count)
        for (position, entry) in entries.enumerated() {
            let folded = entry.names.map(Self.fold)
            var seen = Set<String>()
            for word in folded.flatMap(Self.words) where seen.insert(word).inserted {
                nameWords[word, default: []].append(position)
            }
            var seenFacets = Set<String>()
            for word in entry.facets.map(Self.fold).flatMap(Self.words)
            where !seen.contains(word) && seenFacets.insert(word).inserted {
                facetWords[word, default: []].append(position)
            }
            records.append(Record(
                id: entry.id,
                foldedNames: folded,
                wordCount: folded.first.map { Self.words($0).count } ?? 0,
                sortKey: folded.first ?? ""
            ))
        }
        self.records = records
        self.nameWords = nameWords
        self.facetWords = facetWords
        self.vocabulary = Set(nameWords.keys).union(facetWords.keys).sorted()
    }

    var count: Int { records.count }

    /// Lowercased, with accents and other diacritics removed, so "Śvānāsana"
    /// is found by "svanasana". Applied to names and queries alike.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    static func words(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Words every item of a catalogue could be described by; they are ignored
    /// when the query has other words ("warrior pose" is "warrior").
    var fillerWords: Set<String> = []

    /// Items matching every word of the query, best first. An empty query
    /// matches nothing; the caller shows its unfiltered list for that.
    func search(_ query: String) -> [ID] {
        let folded = Self.fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        var queryWords = Self.words(folded)
        guard !queryWords.isEmpty else { return [] }
        let meaningful = queryWords.filter { !fillerWords.contains($0) }
        if !meaningful.isEmpty { queryWords = meaningful }

        var scores: [Int: Double]?
        for word in queryWords {
            var hits: [Int: Double] = [:]
            func note(_ positions: [Int], _ value: Double) {
                for position in positions where (hits[position] ?? 0) < value {
                    hits[position] = value
                }
            }
            if let exact = nameWords[word] { note(exact, 300) }
            if let exact = facetWords[word] { note(exact, 120) }
            for candidate in wordsWithPrefix(word) where candidate != word {
                if let partial = nameWords[candidate] { note(partial, 200) }
                if let partial = facetWords[candidate] { note(partial, 80) }
            }
            if hits.isEmpty {
                for candidate in wordsNear(word) {
                    if let near = nameWords[candidate] { note(near, 90) }
                    if let near = facetWords[candidate] { note(near, 40) }
                }
            }
            if let current = scores {
                var merged: [Int: Double] = [:]
                for (position, value) in hits {
                    if let before = current[position] { merged[position] = before + value }
                }
                scores = merged
            } else {
                scores = hits
            }
            if scores?.isEmpty == true { return [] }
        }

        let ranked = (scores ?? [:]).map { position, base -> (Int, Double) in
            let record = records[position]
            var score = base
            var best = 0.0
            for name in record.foldedNames {
                if name == folded { best = max(best, 4000) }
                else if name.hasPrefix(folded + " ") || name.hasPrefix(folded + "-") { best = max(best, 3500) }
                else if name.hasPrefix(folded) { best = max(best, 3000) }
                else if name.contains(folded) { best = max(best, 1500) }
            }
            score += best
            // Shorter names first: they are closer to what was typed.
            score -= Double(record.wordCount) * 2
            return (position, score)
        }
        return ranked
            .sorted {
                $0.1 != $1.1 ? $0.1 > $1.1 : records[$0.0].sortKey < records[$1.0].sortKey
            }
            .map { records[$0.0].id }
    }

    private func wordsWithPrefix(_ prefix: String) -> ArraySlice<String> {
        var low = 0
        var high = vocabulary.count
        while low < high {
            let middle = (low + high) / 2
            if vocabulary[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < vocabulary.count, vocabulary[end].hasPrefix(prefix) { end += 1 }
        return vocabulary[low..<end]
    }

    /// Words one typing error away (two for long words). Short words are not
    /// guessed at: too many words are one letter from another.
    private func wordsNear(_ word: String) -> [String] {
        let length = word.count
        guard length >= 4 else { return [] }
        let allowed = length >= 8 ? 2 : 1
        return vocabulary.filter { candidate in
            abs(candidate.count - length) <= allowed
                && word.levenshteinDistance(to: candidate) <= allowed
        }
    }
}
