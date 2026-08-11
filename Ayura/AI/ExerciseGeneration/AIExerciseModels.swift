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
struct AIExercisePracticeDetailsResponse: Codable {
    @Guide(description: "True only when the exact exercise is a yoga asana, pranayama, meditation, mudra, bandha, or kriya.")
    var isYogaPractice: Bool
    @Guide(description: "Established Sanskrit name for a yoga practice. Return an empty string for a non-yoga exercise or when no established Sanskrit name exists.")
    var sanskrit: String
    @Guide(description: "Canonical lowercase Latin slug separated by hyphens. Base it only on the exact exercise name.")
    var slug: String
    @Guide(description: "For yoga, use exactly one of: Arm Balance, Backbend, Bandha & Mudra, Core, Forward Bend, Hip Opener, Inversion, Kriya, Meditation, Pranayama, Prone, Restorative, Seated, Standing, Standing Balance, Supine, Surya Namaskar, Twist. Return an empty string for non-yoga exercises.")
    var family: String
    @Guide(description: "Difficulty from 1 (beginner) to 3 (advanced). Use a realistic level for every exercise.", .range(1...3))
    var level: Int
    @Guide(description: "Typical duration in seconds for one set, hold, or practice. Use 15 to 1800 seconds.", .range(15...1800))
    var durationSeconds: Int
    @Guide(description: "For yoga, use exactly one YogaBreath raw value from the supplied instructions. Return an empty string for non-yoga exercises.")
    var breath: String
    @Guide(description: "For yoga, use exactly one YogaDrishti raw value from the supplied instructions. Return an empty string for non-yoga exercises.")
    var drishti: String
    @Guide(description: "Concrete safety contraindications or situations requiring professional modification for the exact exercise. Return an empty array when none are normally needed.")
    var contraindications: [String]
    @Guide(description: "For yoga, Vata effect from -2 (strongly pacifies) to 2 (strongly aggravates); use 0 for non-yoga.", .range(-2...2))
    var doshaVata: Int
    @Guide(description: "For yoga, Pitta effect from -2 (strongly pacifies) to 2 (strongly aggravates); use 0 for non-yoga.", .range(-2...2))
    var doshaPitta: Int
    @Guide(description: "For yoga, Kapha effect from -2 (strongly pacifies) to 2 (strongly aggravates); use 0 for non-yoga.", .range(-2...2))
    var doshaKapha: Int
}

@available(iOS 26.0, *)
@Generable
struct AIBestExerciseChoice: Codable {
    @Guide(description: "Index of the best candidate from the enumerated list. Return -1 only if none is a strong match.")
    var choiceIndex: Int
    @Guide(description: "One-sentence reason for the choice.")
    var reason: String
}
