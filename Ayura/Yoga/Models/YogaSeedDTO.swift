import Foundation

public struct YogaDosha: Codable, Hashable, Sendable {
    public let vata: Int
    public let pitta: Int
    public let kapha: Int
}

public struct YogaDoshaEffect: Codable, Hashable, Sendable {
    public let vata: Double
    public let pitta: Double
    public let kapha: Double
}

enum YogaPoseSide: String, Codable, Sendable {
    case single
    case both
}

struct YogaSequencePose: Codable, Hashable, Sendable {
    let stage: String
    let id: UUID
    let catalogNumber: Int
    let name: String
    let sanskrit: String
    let seconds: Int
    let side: YogaPoseSide

    var totalSeconds: Int {
        side == .both ? seconds * 2 : seconds
    }
}

struct YogaAsanaDTO: Decodable, Sendable {
    let id: UUID
    let catalogNumber: Int
    let title: String
    let sanskrit: String
    let slug: String
    let desc: String
    let family: AsanaFamily
    let level: Int
    let levelScale: String
    let muscleGroups: [MuscleGroup]
    let metValue: Double
    let minimalAgeMonths: Int
    let durationSeconds: Int
    let breath: String
    let drishti: String
    let contraindications: [String]
    let dosha: YogaDosha
    let doshaProvenance: String
    let assetImageName: String
}

struct YogaSequenceDTO: Decodable, Sendable {
    let id: UUID
    let catalogNumber: Int
    let title: String
    let intent: String
    let level: Int
    let durationMinutes: Int
    let season: String
    let school: String
    let note: String
    let doshaEffect: YogaDoshaEffect
    let doshaProvenance: String
    let estimatedSeconds: Int
    let poses: [YogaSequencePose]
}
