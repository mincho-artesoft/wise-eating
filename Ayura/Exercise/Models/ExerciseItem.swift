import Foundation
import UIKit
import SwiftData

@Model
public final class ExerciseItem: Identifiable {
    #Index<ExerciseItem>([\.name], [\.isUserAdded], [\.nameNormalized])

    @Attribute(.unique) public var id: UUID
    /// Stable number from the bundled catalogue. It is provenance, not identity.
    @Attribute(.unique) public var catalogNumber: Int?

    // 🔎 Search Tokens
    public var searchTokens: [String] = []
    public var searchTokens2: [String] = []

    public var name: String {
        didSet {
            refreshSearchMetadata()
        }
    }
    public var nameNormalized: String

    public var sanskrit: String? {
        didSet { refreshSearchMetadata() }
    }
    public var slug: String?
    public var family: AsanaFamily? {
        didSet { refreshSearchMetadata() }
    }
    public var level: Int?
    @Attribute(originalName: "breath")
    private var breathRawValue: String?
    @Attribute(originalName: "drishti")
    private var drishtiRawValue: String?
    public var breath: YogaBreath? {
        get { breathRawValue.flatMap(YogaBreath.init(rawValue:)) }
        set { breathRawValue = newValue?.rawValue }
    }
    public var drishti: YogaDrishti? {
        get { drishtiRawValue.flatMap(YogaDrishti.init(rawValue:)) }
        set { drishtiRawValue = newValue?.rawValue }
    }
    public var contraindications: [String]?
    public var dosha: YogaDosha?
    public var doshaProvenance: String?
    
    public var exerciseDescription: String?
    public var videoURL: String?
    public var metValue: Double?
    public var isUserAdded: Bool = true
    public var isFavorite: Bool = false
    
    @Attribute(.externalStorage)
    public var photo: Data?
    
    @Relationship(deleteRule: .cascade)
    public var gallery: [ExercisePhoto]?
    
    public var assetImageName: String?
    public var muscleGroups: [MuscleGroup]
    
    @Attribute(originalName: "durationMinutes")
    public var durationSeconds: Int?
    public var isWorkout: Bool = false
    @Relationship(deleteRule: .cascade)
    public var exercises: [ExerciseLink]? = []
    
    /// Minimum age (months)
    public var minimalAgeMonths: Int = 0
    
    @Relationship(inverse: \Node.linkedExercises)
    public var nodes: [Node]? = []

    // MARK: - Tokenizers
    
    static func makeTokens(from name: String) -> [String] {
        // normalize
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "[-/_]", with: " ", options: .regularExpression)
            .folding(options: .diacriticInsensitive, locale: .current)

        // split to raw words
        let raw = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        // drop stopwords/negators
        let stop: Set<String> = [
            "and","or","with","without","in","of","the","a","an",
            "style","type","made","from","plus","no","low","reduced"
        ]
        let negators: Set<String> = ["excluding","except","without","no"]
        let words = raw.filter { !stop.contains($0) }

        // unigrams
        var tokens = words

        // bigrams
        if words.count >= 2 {
            for i in 0..<(words.count-1) {
                tokens.append(words[i] + " " + words[i+1])
            }
        }
        // trigrams
        if words.count >= 3 {
            for i in 0..<(words.count-2) {
                tokens.append(words[i] + " " + words[i+1] + " " + words[i+2])
            }
        }

        // keep negators
        tokens.append(contentsOf: raw.filter { negators.contains($0) })
        return tokens
    }
    
    static func makeTokens2(from name: String) -> [String] {
        return name
          .lowercased()
          .folding(options: .diacriticInsensitive, locale: .current)
          .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
          .map { String($0) }
    }
    
    public init(
        id: UUID = UUID(),
        catalogNumber: Int? = nil,
        name: String,
        sanskrit: String? = nil,
        slug: String? = nil,
        family: AsanaFamily? = nil,
        level: Int? = nil,
        breath: YogaBreath? = nil,
        drishti: YogaDrishti? = nil,
        contraindications: [String]? = nil,
        dosha: YogaDosha? = nil,
        doshaProvenance: String? = nil,
        description: String? = nil,
        videoURL: String? = nil,
        metValue: Double? = nil,
        isUserAdded: Bool = true,
        photo: Data? = nil,
        gallery: [ExercisePhoto]? = nil,
        assetImageName: String? = nil,
        muscleGroups: [MuscleGroup],
        durationSeconds: Int? = nil,
        isWorkout: Bool = false,
        exercises: [ExerciseLink]? = [],
        minimalAgeMonths: Int? = 0
    ) {
        self.id = id
        self.catalogNumber = catalogNumber
        self.name = name
        self.nameNormalized = name.foldedSearchKey

        self.sanskrit = sanskrit
        self.slug = slug
        self.family = family
        self.level = level
        self.breathRawValue = breath?.rawValue
        self.drishtiRawValue = drishti?.rawValue
        self.contraindications = contraindications
        self.dosha = dosha
        self.doshaProvenance = doshaProvenance

        // 🔎 Init tokens
        self.searchTokens = []
        self.searchTokens2 = []

        self.exerciseDescription = description
        self.videoURL = videoURL
        self.metValue = metValue
        self.isUserAdded = isUserAdded
        self.photo = photo
        self.gallery = gallery
        self.assetImageName = assetImageName
        self.muscleGroups = muscleGroups
        self.durationSeconds = durationSeconds
        self.isWorkout = isWorkout
        self.exercises = exercises
        self.minimalAgeMonths = minimalAgeMonths ?? 0
        refreshSearchMetadata()
    }
    
    @MainActor
       func update(from dto: ExerciseItemDTO) {
           self.exerciseDescription = dto.desc
           self.metValue = dto.metValue
           self.muscleGroups = dto.muscleGroups
           self.minimalAgeMonths = dto.minimalAgeMonths ?? 0
           self.sanskrit = dto.sanskrit
           self.slug = dto.slug
           self.family = dto.family
           self.level = dto.level
           self.durationSeconds = dto.durationSeconds
           self.breath = dto.breath
           self.drishti = dto.drishti
           self.contraindications = dto.contraindications
           self.dosha = dto.dosha
           self.doshaProvenance = dto.doshaProvenance
           self.assetImageName = dto.assetImageName
           refreshSearchMetadata()
       }

    func refreshSearchMetadata() {
        let searchableText = [name, sanskrit, family?.rawValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        nameNormalized = searchableText.foldedSearchKey
        searchTokens = ExerciseItem.makeTokens(from: searchableText)
        searchTokens2 = ExerciseItem.makeTokens2(from: searchableText)
    }
    
    func exerciseImage(variant: String = "480") -> UIImage? {
       // A) Check DB photo
        if let data = self.photo, let img = UIImage(data: data) {
           return img
       }

       // The same materialized UUID is written by YogaSeeder and keys the
       // archive, so renames and catalogue provenance never affect imagery.
       if let image = YogaVideoSource.shared.getFrame(id: self.id, variant: variant) {
           return image
       }

       if let assetImageName, let image = UIImage(named: assetImageName) {
           return image
       }

       let original = self.name
       let folded   = original.folding(options: .diacriticInsensitive, locale: .current)

       // Requires String+Extension.swift to have assetKeyStrict/Collapsed
       let candidates: [String] = [
           original.assetKeyStrict(),
           folded.assetKeyStrict(),
           original.assetKeyCollapsed(),
           folded.assetKeyCollapsed()
       ]

       for key in candidates {
           if let img = UIImage(named: key) {
               return img
           }
       }

       // Workouts without their own cover use the first available exercise
       // image. An explicitly attached workout photo always wins above.
       if isWorkout, let exercises {
           for link in exercises {
               guard let exercise = link.exercise,
                     exercise.id != id,
                     !exercise.isWorkout,
                     let image = exercise.exerciseImage() else {
                   continue
               }
               return image
           }
       }

       return nil
   }
}

// Hashable
extension ExerciseItem: Hashable {
    public static func == (lhs: ExerciseItem, rhs: ExerciseItem) -> Bool {
        lhs.id == rhs.id && lhs.persistentModelID == rhs.persistentModelID
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
