// ==== FILE: /Users/aleksandarsvinarov/Desktop/Repo/vitahealth2/WiseEating/Exercise/Enums/MuscleGroup.swift ====
import Foundation

/// Represents a major muscle group targeted by an exercise.
/// Codable: Allows SwiftData to save this enum.
/// CaseIterable: Allows you to easily get all possible muscle groups (e.g., for a picker).
/// Identifiable: Useful for SwiftUI lists and ForEach loops.
public enum MuscleGroup: String, Codable, CaseIterable, Identifiable, SelectableItem, Sendable {
    public var id: String { self.rawValue }
    public var name: String { self.rawValue }
    public var iconName: String? { self.rawValue }
    public var iconText: String? { self.rawValue }

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
}

