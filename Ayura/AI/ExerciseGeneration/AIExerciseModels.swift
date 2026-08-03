// ==== FILE: Ayura/AI/ExerciseGeneration/AIExerciseGenerableEnums.swift ====
import Foundation
import FoundationModels

// MARK: - AI-only enums (used by FoundationModels @Generable)
// Тези енуми са отделени, за да не "заключим" домейн слоевете към iOS 26/AI.

// -------------------- AIMuscleGroup --------------------
@available(iOS 26.0, *)
@Generable
public enum AIMuscleGroup: String, Codable, CaseIterable, Sendable {
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

// MARK: - Mapping to/from domain enums

@available(iOS 26.0, *)
public extension AIMuscleGroup {
    @inlinable func toDomain() -> MuscleGroup? { MuscleGroup(rawValue: rawValue) }
}
public extension MuscleGroup {
    @available(iOS 26.0, *)
    @inlinable var ai: AIMuscleGroup? { AIMuscleGroup(rawValue: rawValue) }
}

@available(iOS 26.0, *)
@Generable
struct AIExerciseDescriptionResponse: Codable {
    @Guide(description: "A concise, helpful description of the exercise, focusing on proper form and main benefits.")
    var description: String
}

@available(iOS 26.0, *)
@Generable
struct AIExerciseMETValueResponse: Codable {
    @Guide(description: "A typical Metabolic Equivalent (MET) value for the exercise. Should be a floating-point number.")
    var metValue: Double
}

// 🔁 Ползваме AI енуми тук:
@available(iOS 26.0, *)
@Generable
struct AIExerciseMuscleGroupsResponse: Codable {
    @Guide(description: "An array of primary muscle groups targeted, using only the provided enum cases.")
    var muscleGroups: [AIMuscleGroup]
}

@available(iOS 26.0, *)
@Generable
struct AIExerciseMinAgeResponse: Codable {
    @Guide(description: "The estimated minimum suitable age in months for a child to safely perform a variation of this exercise. E.g., 192 for 16 years.")
    var minAgeMonths: Int
}

@available(iOS 26.0, *)
@Generable
struct AIBestExerciseChoice: Codable {
    @Guide(description: "Index of the best candidate from the enumerated list. Return -1 only if none is a strong match.")
    var choiceIndex: Int
    @Guide(description: "One-sentence reason for the choice.")
    var reason: String
}
