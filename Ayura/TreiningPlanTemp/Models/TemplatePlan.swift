import Foundation
import SwiftData

// Тези модели живеят в AyuraTemplates.store

@Model
final class TemplatePlan: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String

    @Relationship(deleteRule: .cascade, inverse: \TemplateDay.plan)
    public var days: [TemplateDay] = []

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
