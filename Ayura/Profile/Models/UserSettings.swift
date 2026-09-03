// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/AyurvedaAsanaYoga-clean/AyurvedaAsanaYoga/Profile/Models/UserSettings.swift ====
import Combine
import SwiftData
import Foundation

@Model
class UserSettings: ObservableObject {
    var id: UUID = UUID()

    /// Последно избраният профил
    var lastSelectedProfile: Profile?

    /// Единственият профил, към който се отнасят данните от HealthKit.
    var healthKitProfileID: UUID?

    // MARK: - General Settings
    var isAIButtonEnabled: Bool = true
    
    // MARK: - AI Generation Settings
    var generateLipids: Bool = false
    var generateAminoAcids: Bool = false
    var generateCarbDetails: Bool = false
    var generateSterols: Bool = false

    init(
        lastSelectedProfile: Profile? = nil,
        healthKitProfileID: UUID? = nil,
        isAIButtonEnabled: Bool = true,
        generateLipids: Bool = false,
        generateAminoAcids: Bool = false,
        generateCarbDetails: Bool = false,
        generateSterols: Bool = false
    ) {
        self.lastSelectedProfile   = lastSelectedProfile
        self.healthKitProfileID = healthKitProfileID
        self.isAIButtonEnabled     = isAIButtonEnabled 
        self.generateLipids = generateLipids
        self.generateAminoAcids = generateAminoAcids
        self.generateCarbDetails = generateCarbDetails
        self.generateSterols = generateSterols
    }
}
