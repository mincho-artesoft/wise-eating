import Combine
import SwiftData
import Foundation

@Model
class UserSettings: ObservableObject {
    var id: UUID = UUID()

    /// Последно избраният профил (остава, за да не пипаме стария код).
    var lastSelectedProfile: Profile?

    /// НОВО: списък с допълнително избрани профили
    /// (ще го зареждаме в `selectedProfiles`, виж по-долу).
    @Relationship(deleteRule: .nullify)
    var lastSelectedProfiles: [Profile] = []

    init(lastSelectedProfile: Profile? = nil,
         lastSelectedProfiles: [Profile] = []) {
        self.lastSelectedProfile   = lastSelectedProfile
        self.lastSelectedProfiles  = lastSelectedProfiles
    }
}
