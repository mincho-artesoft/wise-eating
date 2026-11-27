import Foundation

/// The text of the guided practices and of the yoga catalogue in the user's
/// language: one table per catalogue, English string to translation, packed
/// like `RecipeContentLocalizer`.
///
///     practice_content.en.z / practice_content.<language>.z
///     yoga_content.en.z     / yoga_content.<language>.z
///
/// Written by `tools/pack_content.py` from `tools/practice-content` and
/// `tools/yoga-content`. The stored models stay English; a view asks for the
/// text to show. A string without a translation (and anything a person wrote
/// themselves) is returned as it is.
struct CatalogTextLocalizer: Sendable {
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

    /// The translation, or nil when the table has none. The keys were written
    /// with runs of white space collapsed, so the lookup does the same.
    func translation(of english: String) -> String? {
        if let direct = translations[english] { return direct }
        let cleaned = english.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned == english ? nil : translations[cleaned]
    }

    func text(_ english: String) -> String {
        translation(of: english) ?? english
    }

    // MARK: Active language

    nonisolated(unsafe) static var practices: CatalogTextLocalizer? = bundled(
        "practice_content", for: Locale.preferredLanguages.first ?? "en"
    )

    nonisolated(unsafe) static var yoga: CatalogTextLocalizer? = bundled(
        "yoga_content", for: Locale.preferredLanguages.first ?? "en"
    )

    static func bundled(
        _ prefix: String,
        for languageIdentifier: String,
        in bundle: Bundle = .main
    ) -> CatalogTextLocalizer? {
        guard let english = lines(of: "\(prefix).en", in: bundle) else { return nil }
        for language in FoodNameLocalizer.candidates(for: languageIdentifier) where language != "en" {
            if let translated = lines(of: "\(prefix).\(language)", in: bundle),
               translated.count >= english.count {
                return CatalogTextLocalizer(language: language, english: english, translated: translated)
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

// MARK: - Practices

extension Practice {
    var displayTitle: String { CatalogTextLocalizer.practices?.text(title) ?? title }

    var displaySanskrit: String? {
        guard let sanskrit, !sanskrit.isEmpty else { return nil }
        return CatalogTextLocalizer.practices?.text(sanskrit) ?? sanskrit
    }

    var displayDescription: String {
        CatalogTextLocalizer.practices?.text(practiceDescription) ?? practiceDescription
    }

    var displaySourceTradition: String {
        CatalogTextLocalizer.practices?.text(sourceTradition) ?? sourceTradition
    }

    /// Everything the list's search should also find the practice by, in the
    /// user's language. Empty in English.
    var localizedSearchValues: [String] {
        guard let localizer = CatalogTextLocalizer.practices else { return [] }
        let english = [title, sanskrit ?? "", practiceDescription, technique, sourceTradition,
                       kind, posture, eyes, guna, agni]
            + goals + themes + timeOfDay + season + contraindications + script.map(\.text)
        return english.compactMap { localizer.translation(of: $0) }
    }
}

extension PracticeCue {
    /// The cue as shown on screen; `text` stays English for the voice and
    /// for the timing derived from its word count.
    var displayText: String { CatalogTextLocalizer.practices?.text(text) ?? text }
}

/// A one-word practice label (kind, posture, eyes, time of day…) in the
/// user's language, or nil in English, where each view has its own wording.
func practiceLabel(_ value: String) -> String? {
    guard let local = CatalogTextLocalizer.practices?.translation(of: value), let first = local.first else {
        return nil
    }
    return String(first).localizedUppercase + local.dropFirst()
}

/// A practice title stored in English (history, reminders) as it is shown.
func localizedPracticeTitle(_ title: String) -> String {
    CatalogTextLocalizer.practices?.text(title) ?? title
}

// MARK: - Yoga

extension ExerciseItem {
    /// The description to show: translated for a catalogue pose, as written
    /// for anything the person added.
    var displayDescription: String? {
        guard let raw = exerciseDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return CatalogTextLocalizer.yoga?.text(raw) ?? raw
    }
}

/// A breath, gaze or caution label of a pose in the user's language.
func yogaLabel(_ value: String) -> String {
    CatalogTextLocalizer.yoga?.text(value) ?? value
}
