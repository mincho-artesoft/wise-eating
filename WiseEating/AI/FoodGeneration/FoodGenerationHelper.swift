import SwiftData

@MainActor
func normalizeDietKey(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
     .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
     .lowercased()
}

@MainActor
func titleCase(_ s: String) -> String {
    s.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
}

/// Взима всички имена на диети от базата (за да ограничим AI да избира само от тях).
@MainActor
func dbDietNames(in ctx: ModelContext) throws -> [String] {
    try ctx.fetch(FetchDescriptor<Diet>()).map(\.name)
}

/// Намира Diet.id по дадени имена; ако няма запис и `createIfMissing == true`, създава нов Diet.
@MainActor
func resolveDietIDs(
    from names: Set<String>,
    in ctx: ModelContext,
    createIfMissing: Bool = true
) throws -> Set<Diet.ID> {
    let all = try ctx.fetch(FetchDescriptor<Diet>())
    var byKey = Dictionary(uniqueKeysWithValues: all.map { (normalizeDietKey($0.name), $0) })
    var ids = Set<Diet.ID>()

    for raw in names {
        let key = normalizeDietKey(raw)
        if let d = byKey[key] {
            ids.insert(d.id)
            continue
        }
        guard createIfMissing else { continue }
        let pretty = titleCase(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        let new = Diet(name: pretty, isDefault: false)
        ctx.insert(new)
        byKey[key] = new
        ids.insert(new.id)
    }

    try ctx.save()
    return ids
}

@available(iOS 26.0, *)
@inline(__always)
func replaceIfZero(_ lhs: inout AINutrient, with rhs: AINutrient) {
    // ако текущата стойност е 0, а новата е ненулева – взимаме новата
    // (по желание: може да добавиш проверка units да съвпадат)
    if lhs.value == 0, rhs.value != 0 {
        lhs = rhs
    }
}
