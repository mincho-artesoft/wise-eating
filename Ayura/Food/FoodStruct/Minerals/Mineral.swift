import SwiftData
import Foundation

@Model
public final class Mineral: Identifiable, Hashable, SelectableItem {
    @Attribute(.unique) public var id: String
    @Attribute(.unique) public var name: String
    public var unit: String
    public var symbol: String
    public var colorHex: String

    @Relationship(deleteRule: .cascade)
    public var requirements: [Requirement] = []

    @Relationship(inverse: \Profile.priorityMinerals)
    public var profiles: [Profile] = []
    
    public init(id: String, name: String, unit: String, symbol: String, colorHex: String, requirements: [Requirement] = []) {
        self.id = id
        self.name = name
        self.unit = unit
        self.symbol = symbol
        self.colorHex = colorHex
        self.requirements = requirements
    }

    // MARK: - SelectableItem Conformance
    public var iconName: String? { nil }
    public var iconText: String? { self.symbol }
}

extension Mineral: ColorSelectableItem {
    public var displayText: String? { symbol }         // или: symbol
}
