import Foundation

/// Command words of one language, as data.
///
/// The search engine parses commands in English ("low fat", "protein > 20",
/// "without gluten", "ph below 5"). A grammar file maps the words a speaker
/// of another language types for those commands to the English ones, so the
/// one tested parser serves every language and a new language is a new file:
///
///     Grammar/search_grammar.<language>.json
///     {
///       "language": "bg",
///       "decimalComma": true,
///       "phrases": { "без": "without", "между # и #": "between # and #" },
///       "keep": ["кисело мляко"]
///     }
///
/// `phrases` maps a phrase of up to five words to its English command; `#`
/// stands for a number. `keep` lists food names that contain a command word
/// and must be left as they are ("кисело мляко" is yogurt, not "acidic milk").
/// Only command words belong here; food names are found through the index.
struct SearchGrammar: Sendable {
    let language: String
    private let phrases: [String: String]
    private let keep: Set<String>
    private let decimalComma: Bool
    private let longestPhrase: Int

    private struct File: Decodable {
        let language: String
        let decimalComma: Bool?
        let phrases: [String: String]
        let keep: [String]?
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        language = file.language
        decimalComma = file.decimalComma ?? false
        var table: [String: String] = [:]
        for (phrase, command) in file.phrases {
            table[Self.key(phrase)] = command
        }
        phrases = table
        keep = Set((file.keep ?? []).map(Self.key))
        longestPhrase = (Array(table.keys) + Array(keep))
            .map { $0.split(separator: " ").count }
            .max() ?? 1
    }

    /// Every phrase of the file and the English command it stands for.
    var allPhrases: [String: String] { phrases }

    private static func key(_ phrase: String) -> String {
        phrase.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private struct Token {
        let text: String
        let isNumber: Bool
        let range: Range<String.Index>
    }

    private func tokens(of query: String) -> [Token] {
        var out: [Token] = []
        var index = query.startIndex
        while index < query.endIndex {
            let character = query[index]
            if character.isNumber {
                var end = query.index(after: index)
                var seenSeparator = false
                while end < query.endIndex {
                    let next = query[end]
                    if next.isNumber {
                        end = query.index(after: end)
                    } else if !seenSeparator, next == "." || (decimalComma && next == ","),
                              query.index(after: end) < query.endIndex,
                              query[query.index(after: end)].isNumber {
                        seenSeparator = true
                        end = query.index(after: end)
                    } else {
                        break
                    }
                }
                let text = query[index..<end].replacingOccurrences(of: ",", with: ".")
                out.append(Token(text: text, isNumber: true, range: index..<end))
                index = end
            } else if character.isLetter {
                var end = query.index(after: index)
                while end < query.endIndex, query[end].isLetter || query[end].isNumber {
                    end = query.index(after: end)
                }
                out.append(Token(text: String(query[index..<end]), isNumber: false, range: index..<end))
                index = end
            } else {
                index = query.index(after: index)
            }
        }
        return out
    }

    /// The query with this language's command phrases replaced by the English
    /// commands. Everything else, food names included, is left untouched.
    func normalize(_ query: String) -> String {
        let lower = query.lowercased()
        let words = tokens(of: lower)
        guard !words.isEmpty else { return query }

        func joinsAsPhrase(_ from: Int, _ to: Int) -> Bool {
            // Words of one phrase are separated by spaces or hyphens only.
            for position in from..<to {
                let gap = lower[words[position].range.upperBound..<words[position + 1].range.lowerBound]
                if !gap.allSatisfy({ $0 == " " || $0 == "-" }) { return false }
            }
            return true
        }

        var result = ""
        var cursor = lower.startIndex
        var position = 0
        while position < words.count {
            var consumed = 0
            var replacement: String?
            let longest = min(longestPhrase, words.count - position)
            for length in stride(from: longest, through: 1, by: -1) {
                guard joinsAsPhrase(position, position + length - 1) else { continue }
                let slice = words[position..<(position + length)]
                let literal = slice.map(\.text).joined(separator: " ")
                if keep.contains(literal) {
                    consumed = length
                    break
                }
                let pattern = slice.map { $0.isNumber ? "#" : $0.text }.joined(separator: " ")
                // A number is part of a phrase only where the phrase asks for one.
                guard let command = phrases[pattern] ?? phrases[literal] else { continue }
                if pattern != literal, phrases[pattern] == nil { continue }
                var numbers = slice.filter(\.isNumber).map(\.text).makeIterator()
                replacement = phrases[pattern] != nil
                    ? command.split(separator: " ", omittingEmptySubsequences: false)
                        .map { $0 == "#" ? (numbers.next() ?? "#") : String($0) }
                        .joined(separator: " ")
                    : command
                consumed = length
                break
            }
            // A unit after a number an earlier phrase already took
            // ("под 140 мг": "под 140" is one phrase, "мг" follows its number).
            if consumed == 0, position > 0, words[position - 1].isNumber, !words[position].isNumber,
               joinsAsPhrase(position - 1, position),
               let command = phrases["# " + words[position].text], command.hasPrefix("# ") {
                replacement = String(command.dropFirst(2))
                consumed = 1
            }
            if consumed == 0 {
                // An ordinary word: copy it, writing a decimal comma as a point.
                result += lower[cursor..<words[position].range.lowerBound]
                result += words[position].text
                cursor = words[position].range.upperBound
                position += 1
                continue
            }
            let last = words[position + consumed - 1]
            result += lower[cursor..<words[position].range.lowerBound]
            result += replacement ?? String(lower[words[position].range.lowerBound..<last.range.upperBound])
            cursor = last.range.upperBound
            position += consumed
        }
        result += lower[cursor...]
        return result
    }

    /// The English command words a single word of this language stands for;
    /// empty when the word is not a command word.
    func commandWords(for word: String) -> [String] {
        guard let command = phrases[Self.key(word)] else { return [] }
        return command.split(separator: " ").map(String.init)
    }

    /// Whether the words at this position start a food name the file protects.
    func isKept(_ words: [String]) -> Bool {
        keep.contains(Self.key(words.joined(separator: " ")))
    }

    // MARK: Active grammar

    /// The grammar of the user's language, or nil for English, for a language
    /// without a file, or when the app runs in a language it has none for.
    nonisolated(unsafe) static var active: SearchGrammar? = bundled(
        for: Locale.preferredLanguages.first ?? "en"
    )

    static func bundled(for languageIdentifier: String, in bundle: Bundle = .main) -> SearchGrammar? {
        for language in FoodNameLocalizer.candidates(for: languageIdentifier) where language != "en" {
            if let url = bundle.url(forResource: "search_grammar.\(language)", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let grammar = try? SearchGrammar(data: data) {
                return grammar
            }
        }
        return nil
    }

    /// Every grammar file in the bundle, for the test that checks them.
    static func allBundled(in bundle: Bundle = .main) -> [SearchGrammar] {
        (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("search_grammar.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? SearchGrammar(data: Data(contentsOf: $0)) }
    }
}
