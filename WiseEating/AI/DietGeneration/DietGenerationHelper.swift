import SwiftData
import Foundation

// MARK: - Utils

func shortID(for id: PersistentIdentifier) -> String {
    let v = UInt(bitPattern: id.hashValue)
    return String(v, radix: 36)
}

func formatTimeInterval(_ interval: TimeInterval) -> String {
    guard interval.isFinite else { return "Calculating..." }
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.zeroFormattingBehavior = .pad
    return f.string(from: interval) ?? "N/A"
}



func asciiClean(_ s: String) -> String {
    let scalars = s.unicodeScalars.filter { $0.isASCII }
    var out = String(String.UnicodeScalarView(scalars))
    out = out.replacingOccurrences(of: #"[^A-Za-z0-9 \-]"#, with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

func heuristicDietName(from prompts: [String]) -> String {
    let l = prompts.joined(separator: " ").lowercased()
    var tags: [String] = []
    if l.contains("vegan") { tags.append("Vegan") }
    if l.contains("vegetarian") { tags.append("Vegetarian") }
    if l.contains("keto") { tags.append("Keto") }
    if l.contains("low carb") || l.contains("low-carb") { tags.append("Low Carb") }
    if l.contains("high protein") || l.contains("protein") { tags.append("High Protein") }
    if l.contains("mediterranean") { tags.append("Mediterranean") }
    if l.contains("paleo") { tags.append("Paleo") }
    if l.contains("gluten") { tags.append("Gluten Free") }
    if l.contains("dairy") || l.contains("lactose") { tags.append("Dairy Free") }
    if l.contains("sodium") { tags.append("Low Sodium") }
    if l.contains("sugar") { tags.append("Low Sugar") }
    if tags.isEmpty { return "Balanced Diet" }
    return tags.prefix(2).joined(separator: " ")
}
// MARK: - Name normalization & matching

func normalizedAsciiLowercased(_ s: String) -> String {
    // маха диакритици, прави lower, свива интервали и тирета
    let decomposed = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let asciiOnly = decomposed.unicodeScalars.filter { $0.isASCII }
    var out = String(String.UnicodeScalarView(asciiOnly)).lowercased()
    out = out.replacingOccurrences(of: #"[^a-z0-9\-\s]"#, with: " ", options: .regularExpression)
    out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return out
}

func nameContainsAnyKeyword(name: String, keywords: [String]) -> Bool {
    if keywords.isEmpty { return false }
    let needleName = normalizedAsciiLowercased(name)
    for raw in keywords {
        let k = normalizedAsciiLowercased(raw)
        // прескачаме твърде къси и общи термини
        if k.count < 3 { continue }
        // търсим подниз с граници по-скоро "фразово"
        // добавяме интервали, за да намалим фалшиви съвпадения (напр. "pea" в "peach")
        let wrapped = " \(needleName) "
        let target = " \(k) "
        if wrapped.contains(target) { return true }
        // fallback: директно contains, ако горното не хване тирета/комбинации
        if needleName.contains(k) { return true }
    }
    return false
}
