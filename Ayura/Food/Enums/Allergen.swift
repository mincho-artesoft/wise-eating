public enum Allergen: String, Codable, CaseIterable, Identifiable, SelectableItem, Sendable {
    public var id: String { rawValue }
    public var name: String { self.rawValue }
    public var displayName: String {
        switch self {
        case .celery: String(localized: "Celery")
        case .cerealsContainingGluten: String(localized: "Cereals containing gluten")
        case .cerealsContainingGlutenBarley: String(localized: "Cereals containing gluten (barley)")
        case .cerealsContainingGlutenOats: String(localized: "Cereals containing gluten (oats)")
        case .cerealsContainingGlutenRye: String(localized: "Cereals containing gluten (rye)")
        case .crustaceans: String(localized: "Crustaceans")
        case .eggs: String(localized: "Eggs")
        case .fish: String(localized: "Fish")
        case .lowSodium: String(localized: "Low Sodium")
        case .milk: String(localized: "Milk")
        case .molluscs: String(localized: "Molluscs")
        case .mustard: String(localized: "Mustard")
        case .nuts: String(localized: "Nuts")
        case .nutsBrazilNuts: String(localized: "Nuts (Brazil nuts)")
        case .nutsAlmonds: String(localized: "Nuts (almonds)")
        case .nutsCashews: String(localized: "Nuts (cashews)")
        case .nutsChestnuts: String(localized: "Nuts (chestnuts)")
        case .nutsCoconut: String(localized: "Nuts (coconut)")
        case .nutsHazelnuts: String(localized: "Nuts (hazelnuts)")
        case .nutsMacadamiaNuts: String(localized: "Nuts (macadamia nuts)")
        case .nutsPecans: String(localized: "Nuts (pecans)")
        case .nutsPineNuts: String(localized: "Nuts (pine nuts)")
        case .nutsPistachioNuts: String(localized: "Nuts (pistachio nuts)")
        case .nutsWalnuts: String(localized: "Nuts (walnuts)")
        case .peanuts: String(localized: "Peanuts")
        case .sesameSeeds: String(localized: "Sesame seeds")
        case .soybeans: String(localized: "Soybeans")
        case .sulphurDioxideSulphites: String(localized: "Sulphur dioxide/sulphites")
        }
    }

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
