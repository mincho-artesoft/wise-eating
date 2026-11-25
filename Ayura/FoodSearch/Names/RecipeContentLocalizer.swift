import Foundation

/// Recipe steps, Ayurvedic guidance, dravya descriptions, contraindications,
/// and viruddha notes in the user's language, packed identically to
/// `FoodNameLocalizer`.
///
///     recipe_content.en.z          unique English strings, one per line
///     recipe_content.<language>.z  aligned translations, same order
///
/// Both are raw-DEFLATE UTF-8 text written by `tools/recipe-content/pack.py`.
/// Strings without a translation (including user-created entries) stay as-is.
struct RecipeContentLocalizer: Sendable {
    let language: String
    private let translations: [String: String]

    init(language: String, english: [String], translated: [String]) {
        self.language = language
        var table: [String: String] = [:]
        table.reserveCapacity(translated.count)
        for (source, local) in zip(english, translated) where !local.isEmpty && local != source {
            table[source] = local
        }
        translations = table
    }

    /// Translates a single string (step, guidance, prabhava, preparation,
    /// contraindication, or viruddha note) if present in the catalogue table.
    func localizedText(_ english: String) -> String {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        return translations[trimmed] ?? english
    }

    /// Translates a seeded `FoodItem.itemDescription`, preserving paragraph
    /// breaks (`\n\n`) and numbered recipe step prefixes (`1. `, `2. `, ...).
    func localizedDescription(_ description: String) -> String {
        let paragraphs = description.components(separatedBy: "\n\n")
        let translated = paragraphs.map { paragraph -> String in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if let direct = translations[trimmed] {
                return direct
            }
            let lines = paragraph.components(separatedBy: "\n")
            guard lines.count > 1 || Self.numberedPrefix(in: trimmed) != nil else {
                return paragraph
            }
            return lines.map { line -> String in
                let clean = line.trimmingCharacters(in: .whitespaces)
                if let direct = translations[clean] {
                    return direct
                }
                if let (prefix, body) = Self.numberedPrefix(in: clean),
                   let localBody = translations[body] {
                    return prefix + localBody
                }
                return line
            }.joined(separator: "\n")
        }
        return translated.joined(separator: "\n\n")
    }

    private static func numberedPrefix(in line: String) -> (String, String)? {
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isASCII, line[idx].isNumber {
            idx = line.index(after: idx)
        }
        guard idx > line.startIndex, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let bodyStart = line.index(after: afterDot)
        let prefix = String(line[..<bodyStart])
        let body = String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : (prefix, body)
    }

    // MARK: Active language

    nonisolated(unsafe) static var active: RecipeContentLocalizer? = bundled(
        for: Locale.preferredLanguages.first ?? "en"
    )

    static func bundled(for languageIdentifier: String, in bundle: Bundle = .main) -> RecipeContentLocalizer? {
        guard let english = lines(of: "recipe_content.en", in: bundle) else { return nil }
        for language in FoodNameLocalizer.candidates(for: languageIdentifier) where language != "en" {
            if let translated = lines(of: "recipe_content.\(language)", in: bundle),
               translated.count >= english.count {
                return RecipeContentLocalizer(language: language, english: english, translated: translated)
            }
        }
        return nil
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
    /// The description to show: localized recipe steps/guidance or dravya notes
    /// when the catalogue has a translation for the user's language.
    var displayDescription: String? {
        guard let raw = itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return RecipeContentLocalizer.active?.localizedDescription(raw) ?? raw
    }
}
