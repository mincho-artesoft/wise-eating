// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/Profile/Models/UserSettings.swift ====
import Combine
import SwiftData
import Foundation

@Model
class UserSettings: ObservableObject {
    var id: UUID = UUID()

    /// Последно избраният профил
    var lastSelectedProfile: Profile?

    /// Списък с допълнително избрани профили
    @Relationship(deleteRule: .nullify)
    var lastSelectedProfiles: [Profile] = []
    
    // MARK: - AI Generation Settings
    // Тези полета контролират дали AI да генерира детайлните нутриенти
    var generateLipids: Bool = false
    var generateAminoAcids: Bool = false
    var generateCarbDetails: Bool = false
    var generateSterols: Bool = false

    init(
        lastSelectedProfile: Profile? = nil,
        lastSelectedProfiles: [Profile] = [],
        generateLipids: Bool = false,
        generateAminoAcids: Bool = false,
        generateCarbDetails: Bool = false,
        generateSterols: Bool = false
    ) {
        self.lastSelectedProfile   = lastSelectedProfile
        self.lastSelectedProfiles  = lastSelectedProfiles
        self.generateLipids = generateLipids
        self.generateAminoAcids = generateAminoAcids
        self.generateCarbDetails = generateCarbDetails
        self.generateSterols = generateSterols
    }
}
