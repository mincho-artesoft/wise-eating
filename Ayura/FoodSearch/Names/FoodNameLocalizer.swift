import Foundation

/// Food names in the user's language, built from translated name segments.
///
/// Catalogue names are lists of comma-separated segments ("Beef, round,
/// boneless, raw"), and the same 9,000 segments make up all 14,487 names. A
/// language is therefore one file of translated segments, aligned line by line
/// with the English segment list, and a name is translated by translating its
/// segments. A segment with no translation stays English, so partial coverage
/// and foods the user added still read sensibly.
///
///     food_name_segments.en.z   the English segments, one per line
///     food_names.<language>.z   their translations, same order
///
/// Both are raw-DEFLATE text, written by tools/food-names/pack.py.
struct FoodNameLocalizer: Sendable {
    let language: String
    private let translations: [String: String]

    init(language: String, segments: [String], translated: [String]) {
        self.language = language
        var table: [String: String] = [:]
        table.reserveCapacity(segments.count)
        for (english, local) in zip(segments, translated) where !local.isEmpty && local != english {
            table[english] = local
        }
        translations = table
    }

    static func segments(of name: String) -> [String] {
        name.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The name in this language, or nil when none of its segments is translated.
    func localizedName(_ english: String) -> String? {
        var translatedAny = false
        let parts = Self.segments(of: english).map { segment -> String in
            if let local = translations[segment] {
                translatedAny = true
                return local
            }
            return segment
        }
        return translatedAny ? parts.joined(separator: ", ") : nil
    }

    /// The translation of one segment, for building the search index.
    func translation(ofSegment segment: String) -> String? {
        translations[segment]
    }

    /// The words and adjacent word pairs of a localized segment, as the search
    /// index stores them. No stemming and no diacritic folding: the query is
    /// only lowercased, and "й" must not become "и".
    static func searchTokens(of text: String) -> [String] {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        var tokens = words
        if words.count >= 2 {
            for index in 0..<(words.count - 1) {
                tokens.append(words[index] + " " + words[index + 1])
            }
        }
        return tokens
    }

    // MARK: Active language

    /// The names of the user's language, or nil for English and for a
    /// language the bundle has no names for.
    nonisolated(unsafe) static var active: FoodNameLocalizer? = bundled(
        for: Locale.preferredLanguages.first ?? "en"
    )

    static func bundled(for languageIdentifier: String, in bundle: Bundle = .main) -> FoodNameLocalizer? {
        let language = Locale(identifier: languageIdentifier).language.languageCode?.identifier
            ?? languageIdentifier
        guard language != "en",
              let segments = lines(of: "food_name_segments.en", in: bundle),
              let translated = lines(of: "food_names.\(language)", in: bundle),
              segments.count == translated.count
        else { return nil }
        return FoodNameLocalizer(language: language, segments: segments, translated: translated)
    }

    private static func lines(of resource: String, in bundle: Bundle) -> [String]? {
        guard let url = bundle.url(forResource: resource, withExtension: "z"),
              let packed = try? Data(contentsOf: url),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data
        else { return nil }
        return String(decoding: raw, as: UTF8.self).components(separatedBy: "\n")
    }
}

extension FoodItem {
    /// The name to show: in the user's language when the catalogue has it.
    var displayName: String {
        FoodNameLocalizer.active?.localizedName(name) ?? name
    }
}
