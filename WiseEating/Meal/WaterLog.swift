import Foundation
import SwiftData

@Model
public final class WaterLog {
    @Attribute(.unique) public var id: UUID = UUID()
    
    /// Датата на записа, нормализирана до началото на деня (00:00 часа).
    /// Това е ключово за лесното и точно търсене по ден.
    public var date: Date
    
    /// Броят изпити чаши за този ден.
    public var glassesConsumed: Int
    
    /// Обратна връзка към профила-собственик.
    @Relationship(inverse: \Profile.waterLogs)
    public var profile: Profile?
    
    public init(date: Date, glassesConsumed: Int, profile: Profile?) {
        self.id = UUID()
        // Винаги запазваме датата без часове/минути, за да улесним търсенето.
        self.date = Calendar.current.startOfDay(for: date)
        self.glassesConsumed = glassesConsumed
        self.profile = profile
    }
}
