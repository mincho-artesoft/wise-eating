import SwiftData
import Foundation

@Model
public final class Vitamin: Identifiable, Hashable, SelectableItem {
    @Attribute(.unique) public var id: String
    @Attribute(.unique) public var name: String
    public var unit: String
    public var abbreviation: String
    public var colorHex: String

    @Relationship(deleteRule: .cascade)
    public var requirements: [Requirement] = []
    
    @Relationship(inverse: \Profile.priorityVitamins)
    public var profiles: [Profile] = []
    
    public init(id: String, name: String, unit: String, abbreviation: String, colorHex: String, requirements: [Requirement] = []) {
        self.id = id
        self.name = name
        self.unit = unit
        self.abbreviation = abbreviation
        self.colorHex = colorHex
        self.requirements = requirements
    }

    // MARK: - SelectableItem Conformance
    public var iconName: String? { nil }
    public var iconText: String? { self.abbreviation }
}

extension Vitamin: ColorSelectableItem {
    public var displayText: String? { abbreviation }         // или: abbreviation
}
