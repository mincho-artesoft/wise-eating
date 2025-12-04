public enum Allergen: String, Codable, CaseIterable, Identifiable, SelectableItem, Sendable {
    public var id: String { rawValue }
    public var name: String { self.rawValue }
    public var iconName: String? { return self.rawValue.replacingOccurrences(of: "/", with: "_")}
    public var iconText: String? { return self.rawValue.replacingOccurrences(of: "/", with: "_") }

       case celery = "Celery"
       case cerealsContainingGluten = "Cereals containing gluten"
       case cerealsContainingGlutenBarley = "Cereals containing gluten (barley)"
       case cerealsContainingGlutenOats = "Cereals containing gluten (oats)"
       case cerealsContainingGlutenRye = "Cereals containing gluten (rye)"
       case crustaceans = "Crustaceans"
       case eggs = "Eggs"
       case fish = "Fish"
       case lowSodium = "Low Sodium"
       case milk = "Milk"
       case molluscs = "Molluscs"
       case mustard = "Mustard"
       case nuts = "Nuts"
       case nutsBrazilNuts = "Nuts (Brazil nuts)"
       case nutsAlmonds = "Nuts (almonds)"
       case nutsCashews = "Nuts (cashews)"
       case nutsChestnuts = "Nuts (chestnuts)"
       case nutsCoconut = "Nuts (coconut)"
       case nutsHazelnuts = "Nuts (hazelnuts)"
       case nutsMacadamiaNuts = "Nuts (macadamia nuts)"
       case nutsPecans = "Nuts (pecans)"
       case nutsPineNuts = "Nuts (pine nuts)"
       case nutsPistachioNuts = "Nuts (pistachio nuts)"
       case nutsWalnuts = "Nuts (walnuts)"
       case peanuts = "Peanuts"
       case sesameSeeds = "Sesame seeds"
       case soybeans = "Soybeans"
       case sulphurDioxideSulphites = "Sulphur dioxide/sulphites"
}

// MARK: - Allergen grouping / expansion
extension Allergen {
    /// Дефинира "родител" -> "деца" (подалергени), които се считат еквивалентни при филтриране.
    static var parentToChildren: [Allergen: [Allergen]] {
        [
            .cerealsContainingGluten: [
                .cerealsContainingGluten,
                .cerealsContainingGlutenBarley,
                .cerealsContainingGlutenOats,
                .cerealsContainingGlutenRye
            ],
            .nuts: [
                .nuts,
                .nutsBrazilNuts,
                .nutsAlmonds,
                .nutsCashews,
                .nutsChestnuts,
                .nutsCoconut,
                .nutsHazelnuts,
                .nutsMacadamiaNuts,
                .nutsPecans,
                .nutsPineNuts,
                .nutsPistachioNuts,
                .nutsWalnuts
            ]
        ]
    }

    /// Разширява избрания сет от алергени с техните подтипове.
    static func expanded(from selected: Set<Allergen>) -> Set<Allergen> {
        var result = selected
        for parent in selected {
            if let children = parentToChildren[parent] {
                result.formUnion(children)
            }
        }
        return result
    }

    /// Удобство: вход/изход като raw id низове (както се ползват в търсачката).
    static func expandedIDs(from rawIDs: Set<String>) -> Set<String> {
        let selectedEnums = Set(rawIDs.compactMap { Allergen(rawValue: $0) })
        let expandedEnums = expanded(from: selectedEnums)
        return Set(expandedEnums.map(\.rawValue))
    }
}
