import Foundation

public enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    public var id: String { self.rawValue }

    case weightLoss = "Weight Loss"
    case muscleGain = "Muscle Gain"
    case endurance = "Endurance"
    case strength = "Strength"
    case flexibility = "Flexibility"
    case generalFitness = "General Fitness"
    case sportPerformance = "Sport Performance"
    case injuryRecovery = "Injury Recovery"

    var title: String {
        self.rawValue
    }

    var description: String {
        switch self {
        case .weightLoss: "Reduce body weight and body fat"
        case .muscleGain: "Build lean muscle mass"
        case .endurance: "Improve cardiovascular fitness"
        case .strength: "Increase overall power and strength"
        case .flexibility: "Enhance mobility and range of motion"
        case .generalFitness: "Overall health and wellness"
        case .sportPerformance: "Improve athletic performance"
        case .injuryRecovery: "Rehabilitate and prevent injuries"
        }
    }

    var systemImageName: String {
        switch self {
        case .weightLoss: "scalemass.fill"
        case .muscleGain: "chart.line.uptrend.xyaxis"
        case .endurance: "heart.fill"
        case .strength: "bolt.fill"
        case .flexibility: "figure.yoga"
        case .generalFitness: "target"
        case .sportPerformance: "trophy.fill"
        case .injuryRecovery: "shield.fill"
        }
    }
}
