import Foundation

/// A deterministic reading of "for breakfast I ate two eggs and a slice of
/// bread with butter" (English and Bulgarian). It is the on-device fallback
/// when Apple Intelligence is unavailable, and it makes the tool flow testable.
/// It extracts what was said; the catalogue search decides which food it is.
enum AssistantFoodLogParser {
    struct Item: Equatable, Sendable {
        var query: String
        var count: Double?
        var grams: Double?
        var unit: String?
    }

    struct Result: Equatable, Sendable {
        var meal: String?
        var date: String?
        var items: [Item]
    }

    enum Intent: Equatable, Sendable {
        case log, whatDidIEat, unknown
    }

    static func intent(of text: String) -> Intent {
        let t = " " + text.lowercased() + " "
        let question = ["what did i eat", "what have i eaten", "какво ядох", "какво съм ял", "какво съм яла", "what i ate today"]
        if question.contains(where: { t.contains($0) }) { return .whatDidIEat }
        let eat = [" ate ", " eaten ", " i had ", " had a ", " had an ", " drank ", " log ", " add ",
                   "ядох", "изядох", "хапнах", "пих", "изпих", "закусих", "обядвах", "вечерях", " добави ", " запиши "]
        if eat.contains(where: { t.contains($0) }) { return .log }
        return .unknown
    }

    static func parse(_ text: String) -> Result {
        var t = " " + text.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "!", with: " ") + " "

        var meal: String?
        let meals: [(String, [String])] = [
            ("breakfast", ["for breakfast", "at breakfast", "breakfast", "за закуска", "на закуска", "закусих", "закуска"]),
            ("lunch", ["for lunch", "at lunch", "lunch", "за обяд", "на обяд", "обядвах", "обяд"]),
            ("dinner", ["for dinner", "at dinner", "for supper", "dinner", "supper", "за вечеря", "на вечеря", "вечерях", "вечеря"]),
            ("snack", ["as a snack", "for a snack", "snack", "междинно", "за междинна"]),
        ]
        outer: for (name, phrases) in meals {
            for phrase in phrases where t.contains(phrase) {
                meal = name
                t = t.replacingOccurrences(of: phrase, with: " ")
                break outer
            }
        }

        var date: String?
        for (word, value) in [("yesterday", "yesterday"), ("вчера", "yesterday"), ("today", "today"), ("днес", "today")]
        where t.contains(" \(word) ") {
            date = value
            t = t.replacingOccurrences(of: " \(word) ", with: " ")
            break
        }

        let fillers = [" i ate ", " i've eaten ", " i have eaten ", " i had ", " i drank ", " ate ", " had ", " drank ",
                       " please ", " log ", " add ", " this morning ", " tonight ", " i ",
                       " ядох ", " изядох ", " хапнах ", " пих ", " изпих ", " добави ", " запиши ", " моля ", " аз "]
        for f in fillers { t = t.replacingOccurrences(of: f, with: " ") }

        // Split into foods: "and", "with", commas; Bulgarian "и", "с", "със".
        let separators = [",", ";", " and ", " with ", " plus ", " и ", " със ", " с ", " + "]
        var pieces = [t]
        for sep in separators {
            pieces = pieces.flatMap { $0.components(separatedBy: sep) }
        }
        let items = pieces.compactMap(parseItem)
        return Result(meal: meal, date: date, items: items)
    }

    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "half": 0.5, "a couple of": 2, "couple": 2,
        "един": 1, "една": 1, "едно": 1, "два": 2, "две": 2, "три": 3, "четири": 4, "пет": 5,
        "шест": 6, "седем": 7, "осем": 8, "девет": 9, "десет": 10, "половин": 0.5, "половинка": 0.5,
    ]

    private static let gramWords = ["g", "gr", "gram", "grams", "г", "гр", "грама", "грам"]
    private static let kiloWords = ["kg", "кг", "килограм", "килограма"]
    private static let mlWords = ["ml", "мл", "милилитра"]

    private static let unitWords: [String: String] = [
        "slice": "slice", "slices": "slice", "piece": "piece", "pieces": "piece",
        "cup": "cup", "cups": "cup", "glass": "glass", "glasses": "glass", "bowl": "bowl", "bowls": "bowl",
        "tablespoon": "tablespoon", "tablespoons": "tablespoon", "tbsp": "tablespoon",
        "teaspoon": "teaspoon", "teaspoons": "teaspoon", "tsp": "teaspoon", "handful": "handful",
        "of": "",
        "филия": "slice", "филии": "slice", "парче": "piece", "парчета": "piece",
        "чаша": "glass", "чаши": "glass", "купа": "bowl", "купичка": "bowl", "лъжица": "tablespoon",
        "лъжици": "tablespoon", "лъжичка": "teaspoon", "лъжички": "teaspoon", "шепа": "handful",
    ]

    private static func parseItem(_ raw: String) -> Item? {
        var words = raw.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        var count: Double?
        var grams: Double?
        var unit: String?

        // "100g" glued together.
        words = words.flatMap { w -> [String] in
            if let r = w.range(of: #"^(\d+(?:[.,]\d+)?)(g|gr|г|гр|kg|кг|ml|мл)$"#, options: .regularExpression) {
                let s = String(w[r])
                let digits = s.prefix { $0.isNumber || $0 == "." || $0 == "," }
                return [String(digits), String(s.dropFirst(digits.count))]
            }
            return [w]
        }

        var rest: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let next = i + 1 < words.count ? words[i + 1] : nil
            if let n = Double(w.replacingOccurrences(of: ",", with: ".")) {
                if let next, gramWords.contains(next) { grams = n; i += 2; continue }
                if let next, kiloWords.contains(next) { grams = n * 1000; i += 2; continue }
                if let next, mlWords.contains(next) { grams = n; i += 2; continue }
                count = n; i += 1; continue
            }
            if count == nil, rest.isEmpty, let n = numberWords[w] { count = n; i += 1; continue }
            if rest.isEmpty, let u = unitWords[w] {
                if !u.isEmpty { unit = u }
                i += 1; continue
            }
            rest.append(w)
            i += 1
        }
        var query = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if query.count < 2, unit == "slice" {
            // "филия" / "a slice" on its own is a slice of bread.
            let cyrillic = raw.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
            query = cyrillic ? "хляб" : "bread"
        }
        guard query.count >= 2 else { return nil }
        return Item(query: query, count: count, grams: grams, unit: unit)
    }
}

/// Typical portions, so "two eggs" becomes 100 g. The person can change the
/// grams on the preview card before confirming.
enum AssistantPortions {
    private static let byUnit: [String: Double] = [
        "slice": 30, "piece": 100, "cup": 240, "glass": 250, "bowl": 300,
        "tablespoon": 15, "teaspoon": 5, "handful": 30,
    ]

    private static let byFoodWord: [String: Double] = [
        "egg": 50, "eggs": 50, "яйце": 50, "яйца": 50,
        "banana": 120, "банан": 120, "банана": 120, "apple": 180, "ябълка": 180, "ябълки": 180,
        "orange": 150, "портокал": 150, "pear": 170, "круша": 170,
        "bread": 30, "toast": 30, "хляб": 30, "филия": 30,
        "butter": 10, "масло": 10, "cheese": 30, "сирене": 30, "кашкавал": 30,
        "tomato": 120, "домат": 120, "домата": 120, "cucumber": 200, "краставица": 200,
        "potato": 170, "картоф": 170, "картофа": 170,
        "yogurt": 150, "yoghurt": 150, "кисело": 150,
        "milk": 250, "мляко": 250, "coffee": 240, "кафе": 240, "tea": 240, "чай": 240,
        "rice": 150, "ориз": 150, "soup": 300, "супа": 300, "salad": 150, "салата": 150,
        "chicken": 150, "пиле": 150, "пилешко": 150, "fish": 150, "риба": 150,
        "date": 8, "dates": 8, "фурма": 8, "фурми": 8, "almond": 1.2, "almonds": 1.2, "бадем": 1.2, "бадема": 1.2,
    ]

    static func grams(for item: AssistantFoodLogParser.Item) -> Double {
        if let g = item.grams { return g }
        let count = item.count ?? 1
        if let unit = item.unit, let g = byUnit[unit] {
            // "a slice of bread" is a bread slice, "a cup of milk" a cup.
            return count * g
        }
        for word in item.query.split(separator: " ").map(String.init) {
            if let g = byFoodWord[word] { return count * g }
        }
        return count * 100
    }
}
