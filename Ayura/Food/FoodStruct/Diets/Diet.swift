import Foundation
import SwiftData

@Model
public final class Diet: Identifiable, Hashable, SelectableItem {
    @Attribute(.unique) public var id: String
    public var name: String
    public var isDefault: Bool

    @Relationship(deleteRule: .nullify, inverse: \FoodItem.diets)
    public var foods: [FoodItem]?

    @Relationship(inverse: \Profile.diets)
    public var profiles: [Profile]? = []

    public init(name: String, isDefault: Bool = false) {
        self.id = name
        self.name = name
        self.isDefault = isDefault
        self.foods = []
        self.profiles = []
    }

    public static func == (lhs: Diet, rhs: Diet) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - SelectableItem Conformance
    public var iconName: String? { nil }
    public var iconText: String? { nil }
}

nonisolated(unsafe) let defaultDietsList: [Diet] = [
    Diet(name: "Dairy-Free", isDefault: true),
    Diet(name: "Egg-Free", isDefault: true),
    Diet(name: "Fat-Free", isDefault: true),
    Diet(name: "Gluten-Free", isDefault: true),
    Diet(name: "Halal", isDefault: true),
    Diet(name: "High-Protein", isDefault: true),
    Diet(name: "Keto", isDefault: true),
    Diet(name: "Kosher", isDefault: true),
    Diet(name: "Lactose-Free", isDefault: true),
    Diet(name: "Low Sodium", isDefault: true),
    Diet(name: "Low-Carb", isDefault: true),
    Diet(name: "Low-Fat", isDefault: true),
    Diet(name: "Mineral-Rich", isDefault: true),
    Diet(name: "No Added Sugar", isDefault: true),
    Diet(name: "Nut-Free", isDefault: true),
    Diet(name: "Paleo", isDefault: true),
    Diet(name: "Pescatarian", isDefault: true),
    Diet(name: "Soy-Free", isDefault: true),
    Diet(name: "Vegan", isDefault: true),
    Diet(name: "Vegetarian", isDefault: true),
    Diet(name: "Vitamin-Rich", isDefault: true)
]


// Diet+ColorSelectableItem.swift
import Foundation

extension Diet: ColorSelectableItem {
    public var displayText: String? { nil } // не го ползваме
    public var colorHex: String { "" }
}
