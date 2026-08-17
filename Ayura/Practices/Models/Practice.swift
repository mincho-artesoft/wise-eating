import Foundation
import SwiftData

@Model
final class Practice: Identifiable {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var catalogNumber: Int

    var slug: String
    var kind: String
    var title: String
    var sanskrit: String?
    var practiceDescription: String
    var technique: String
    var sourceTradition: String
    var seatAsanaID: UUID?
    var seatFlexible: Bool
    var posture: String
    var eyes: String
    var durationSeconds: Int
    var durationOptions: [Int]
    var goals: [String]
    var themes: [String]
    var level: Int
    var minimalAgeMonths: Int
    var contraindications: [String]
    var isFavorite: Bool = false
    var doshaVata: Int
    var doshaPitta: Int
    var doshaKapha: Int
    var doshaProvenance: String
    var guna: String
    var timeOfDay: [String]
    var season: [String]
    var agni: String
    var sceneImageName: String?
    var narrationAudioAssetName: String?
    var ttsVoiceHint: String
    var wordsPerMinute: Int
    var ambienceTrackID: String
    var ambienceLoops: Bool
    var ambienceVolume: Double
    var timingMode: String

    @Relationship(deleteRule: .cascade, inverse: \PracticeCue.practice)
    var script: [PracticeCue]

    init(
        id: UUID,
        catalogNumber: Int,
        slug: String,
        kind: String,
        title: String,
        sanskrit: String?,
        practiceDescription: String,
        technique: String,
        sourceTradition: String,
        seatAsanaID: UUID?,
        seatFlexible: Bool,
        posture: String,
        eyes: String,
        durationSeconds: Int,
        durationOptions: [Int],
        goals: [String],
        themes: [String],
        level: Int,
        minimalAgeMonths: Int,
        contraindications: [String],
        isFavorite: Bool = false,
        doshaVata: Int,
        doshaPitta: Int,
        doshaKapha: Int,
        doshaProvenance: String,
        guna: String,
        timeOfDay: [String],
        season: [String],
        agni: String,
        sceneImageName: String?,
        narrationAudioAssetName: String?,
        ttsVoiceHint: String,
        wordsPerMinute: Int,
        ambienceTrackID: String,
        ambienceLoops: Bool,
        ambienceVolume: Double,
        timingMode: String,
        script: [PracticeCue] = []
    ) {
        self.id = id
        self.catalogNumber = catalogNumber
        self.slug = slug
        self.kind = kind
        self.title = title
        self.sanskrit = sanskrit
        self.practiceDescription = practiceDescription
        self.technique = technique
        self.sourceTradition = sourceTradition
        self.seatAsanaID = seatAsanaID
        self.seatFlexible = seatFlexible
        self.posture = posture
        self.eyes = eyes
        self.durationSeconds = durationSeconds
        self.durationOptions = durationOptions
        self.goals = goals
        self.themes = themes
        self.level = level
        self.minimalAgeMonths = minimalAgeMonths
        self.contraindications = contraindications
        self.isFavorite = isFavorite
        self.doshaVata = doshaVata
        self.doshaPitta = doshaPitta
        self.doshaKapha = doshaKapha
        self.doshaProvenance = doshaProvenance
        self.guna = guna
        self.timeOfDay = timeOfDay
        self.season = season
        self.agni = agni
        self.sceneImageName = sceneImageName
        self.narrationAudioAssetName = narrationAudioAssetName
        self.ttsVoiceHint = ttsVoiceHint
        self.wordsPerMinute = wordsPerMinute
        self.ambienceTrackID = ambienceTrackID
        self.ambienceLoops = ambienceLoops
        self.ambienceVolume = ambienceVolume
        self.timingMode = timingMode
        self.script = script
    }

    var orderedScript: [PracticeCue] {
        script.sorted {
            if $0.atSeconds == $1.atSeconds { return $0.ordinal < $1.ordinal }
            return $0.atSeconds < $1.atSeconds
        }
    }

    /// Runtime derived from the words actually spoken plus authored holds.
    /// This prevents the UI from offering a duration shorter than its script.
    var computedRuntimeSeconds: Int {
        let pace = max(wordsPerMinute, 1)
        let seconds = orderedScript.reduce(0.0) { total, cue in
            let wordCount = cue.text.split(whereSeparator: \.isWhitespace).count
            let narration = Double(wordCount) / Double(pace) * 60
            return total + narration + Double(cue.holdSeconds)
        }
        return Int(ceil(seconds))
    }

    var availableDurationOptions: [Int] {
        let valid = durationOptions
            .filter { $0 >= computedRuntimeSeconds }
            .sorted()
        return valid.isEmpty ? [max(durationSeconds, computedRuntimeSeconds)] : valid
    }
}

@Model
final class PracticeCue {
    @Attribute(.unique) var id: String
    var ordinal: Int
    var atSeconds: Double
    var text: String
    var holdSeconds: Double
    var practice: Practice?

    init(
        id: String,
        ordinal: Int,
        atSeconds: Double,
        text: String,
        holdSeconds: Double,
        practice: Practice? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.atSeconds = atSeconds
        self.text = text
        self.holdSeconds = holdSeconds
        self.practice = practice
    }
}
