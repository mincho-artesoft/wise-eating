import Foundation
import SwiftData

// Тези модели живеят в templates.store

@Model
final class TemplatePlan: Identifiable {
    @Attribute(.unique) public var id: String
    public var name: String

    @Relationship(deleteRule: .cascade, inverse: \TemplateDay.plan)
    public var days: [TemplateDay] = []

    public init(name: String) {
        self.id = UUID().uuidString
        self.name = name
    }
}
