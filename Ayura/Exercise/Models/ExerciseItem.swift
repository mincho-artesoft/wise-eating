import Foundation
import UIKit
import SwiftData

@Model
public final class ExerciseItem: Identifiable {
    #Index<ExerciseItem>([\.name], [\.isUserAdded], [\.nameNormalized])

    @Attribute(.unique) public var id: Int

    // 🔎 Search Tokens
    public var searchTokens: [String] = []
    public var searchTokens2: [String] = []

    public var name: String {
        didSet {
            self.nameNormalized = name.foldedSearchKey
            self.searchTokens  = ExerciseItem.makeTokens(from: name)
            self.searchTokens2 = ExerciseItem.makeTokens2(from: name)
        }
    }
    public var nameNormalized: String
    
    public var sports: [Sport]?
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
    
    public var durationMinutes: Int?
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
        id: Int,
        name: String,
        sports: [Sport]? = nil,
        description: String? = nil,
        videoURL: String? = nil,
        metValue: Double? = nil,
        isUserAdded: Bool = true,
        photo: Data? = nil,
        gallery: [ExercisePhoto]? = nil,
        assetImageName: String? = nil,
        muscleGroups: [MuscleGroup],
        durationMinutes: Int? = nil,
        isWorkout: Bool = false,
        exercises: [ExerciseLink]? = [],
        minimalAgeMonths: Int? = 0
    ) {
        self.id = id
        self.name = name
        self.nameNormalized = name.foldedSearchKey

        // 🔎 Init tokens
        self.searchTokens  = ExerciseItem.makeTokens(from: name)
        self.searchTokens2 = ExerciseItem.makeTokens2(from: name)

        self.sports = sports
        self.exerciseDescription = description
        self.videoURL = videoURL
        self.metValue = metValue
        self.isUserAdded = isUserAdded
        self.photo = photo
        self.gallery = gallery
        self.assetImageName = assetImageName
        self.muscleGroups = muscleGroups
        self.durationMinutes = durationMinutes
        self.isWorkout = isWorkout
        self.exercises = exercises
        self.minimalAgeMonths = minimalAgeMonths ?? 0
    }
    
    @MainActor
       func update(from dto: ExerciseItemDTO) {
           self.exerciseDescription = dto.desc
           self.metValue = dto.metValue
           self.muscleGroups = dto.muscleGroups
           self.sports = dto.sports
           self.minimalAgeMonths = dto.minimalAgeMonths ?? 0
       }
    
    func exerciseImage() -> UIImage? {
       // A) Check DB photo
        if let data = self.photo, let img = UIImage(data: data) {
           return img
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
