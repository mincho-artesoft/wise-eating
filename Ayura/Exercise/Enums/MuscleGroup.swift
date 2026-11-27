// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/AyurvedaAsanaYoga/AyurvedaAsanaYoga/Exercise/Enums/MuscleGroup.swift ====
import Foundation

/// Represents a major muscle group targeted by an exercise.
/// Codable: Allows SwiftData to save this enum.
/// CaseIterable: Allows you to easily get all possible muscle groups (e.g., for a picker).
/// Identifiable: Useful for SwiftUI lists and ForEach loops.
public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, SelectableItem, Sendable {
    public var id: String { self.rawValue }
    public var name: String { displayName }
    public var iconName: String? { assetName(forGender: "Male") }
    public var iconText: String? { displayName }

    public func assetName(forGender gender: String) -> String {
        let normalizedGender = gender
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let namespace = normalizedGender.hasPrefix("f") ? "female" : "male"
        return "\(namespace)/\(rawValue)"
    }

    case chest = "Chest"
    case back = "Back"
    case lats = "Lats"
    case traps = "Traps"
    case lowerBack = "Lower Back"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case hipFlexors = "Hip Flexors"
    case innerThighs = "Inner Thighs"
    case shoulders = "Shoulders"
    case deltoids = "Deltoids"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case abs = "Abs"
    case obliques = "Obliques"
    case fullBody = "Full Body"
    case legs = "Legs"
    case arms = "Arms"

    public var displayName: String {
        switch self {
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .lats: String(localized: "Lats")
        case .traps: String(localized: "Traps")
        case .lowerBack: String(localized: "Lower Back")
        case .quads: String(localized: "Quads")
        case .hamstrings: String(localized: "Hamstrings")
        case .glutes: String(localized: "Glutes")
        case .calves: String(localized: "Calves")
        case .hipFlexors: String(localized: "Hip Flexors")
        case .innerThighs: String(localized: "Inner Thighs")
        case .shoulders: String(localized: "Shoulders")
        case .deltoids: String(localized: "Deltoids")
        case .biceps: String(localized: "Biceps")
        case .triceps: String(localized: "Triceps")
        case .forearms: String(localized: "Forearms")
        case .abs: String(localized: "Abs")
        case .obliques: String(localized: "Obliques")
        case .fullBody: String(localized: "Full Body")
        case .legs: String(localized: "Legs")
        case .arms: String(localized: "Arms")
        }
    }
}
