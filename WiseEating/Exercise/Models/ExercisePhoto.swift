import SwiftData
import Foundation

@Model
public final class ExercisePhoto: Identifiable {

    @Attribute(.unique) public var id = UUID()
    @Attribute(.externalStorage) public var data: Data
    public var createdAt: Date = Date.now

    // Обратна връзка към ExerciseItem
    @Relationship(inverse: \ExerciseItem.gallery)
    public var exerciseItem: ExerciseItem?

    public init(data: Data, createdAt: Date = Date.now) {
        self.data = data
        self.createdAt = createdAt
    }
}
