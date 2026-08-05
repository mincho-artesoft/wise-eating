import Foundation
import SwiftData

@Model
public final class YogaSequence: Identifiable {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var catalogNumber: Int

    public var title: String
    public var intent: String
    public var level: Int
    @Attribute(originalName: "durationMinutes")
    public var durationSeconds: Int
    public var season: String
    public var school: String
    public var sequenceNote: String?
    public var doshaVata: Double
    public var doshaPitta: Double
    public var doshaKapha: Double
    public var doshaProvenance: String
    public var estimatedSeconds: Int

    @Attribute(.externalStorage)
    private var posesData: Data

    var poses: [YogaSequencePose] {
        (try? JSONDecoder().decode([YogaSequencePose].self, from: posesData)) ?? []
    }

    public var doshaEffect: YogaDoshaEffect {
        YogaDoshaEffect(
            vata: doshaVata,
            pitta: doshaPitta,
            kapha: doshaKapha
        )
    }

    init(
        id: UUID,
        catalogNumber: Int,
        title: String,
        intent: String,
        level: Int,
        durationSeconds: Int,
        season: String,
        school: String,
        sequenceNote: String?,
        doshaEffect: YogaDoshaEffect,
        doshaProvenance: String,
        estimatedSeconds: Int,
        posesData: Data
    ) {
        self.id = id
        self.catalogNumber = catalogNumber
        self.title = title
        self.intent = intent
        self.level = level
        self.durationSeconds = durationSeconds
        self.season = season
        self.school = school
        self.sequenceNote = sequenceNote
        self.doshaVata = doshaEffect.vata
        self.doshaPitta = doshaEffect.pitta
        self.doshaKapha = doshaEffect.kapha
        self.doshaProvenance = doshaProvenance
        self.estimatedSeconds = estimatedSeconds
        self.posesData = posesData
    }

    func update(from dto: YogaSequenceDTO, posesData: Data) {
        title = dto.title
        intent = dto.intent
        level = dto.level
        durationSeconds = dto.durationMinutes * 60
        season = dto.season
        school = dto.school
        sequenceNote = dto.note
        doshaVata = dto.doshaEffect.vata
        doshaPitta = dto.doshaEffect.pitta
        doshaKapha = dto.doshaEffect.kapha
        doshaProvenance = dto.doshaProvenance
        estimatedSeconds = dto.estimatedSeconds
        self.posesData = posesData
    }
}
