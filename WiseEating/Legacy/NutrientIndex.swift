//import Foundation
//import SwiftData
//
///// Съхраняваме и нормализираното име (`nameKey`) за бърз текстов филтър без доп. заявки към DB.
//public struct FoodRank: Codable, Hashable {
//    public let foodID: Int
//    public let value: Double            // стойност на нутриента (в еднаква метрика)
//    public let nameKey: String          // lowercased + без диакритика за търсене
//}
//
//@Model
//final class NutrientIndex {
//    /// "vit_vitaminC", "min_iron", и т.н.
//    @Attribute(.unique)
//    var nutrientID: String
//
//    /// JSON-енкодиран масив от FoodRank, вече сортиран по value (desc).
//    var rankedFoodsData: Data?
//
//    var rankedFoods: [FoodRank] {
//        get {
//            guard let data = rankedFoodsData,
//                  let ranks = try? JSONDecoder().decode([FoodRank].self, from: data) else { return [] }
//            return ranks
//        }
//        set {
//            rankedFoodsData = try? JSONEncoder().encode(newValue)
//        }
//    }
//
//    init(nutrientID: String, rankedFoods: [FoodRank]) {
//        self.nutrientID = nutrientID
//        self.rankedFoods = rankedFoods
//    }
//}
//
//// MARK: - Helpers (pure)
//extension NutrientIndex {
//    
//    // ----- START OF CORRECTION -----
//    // This function is simplified to perform a single-phase search.
//    // The concept of `startsWith` vs `contains` phases is removed for nutrient-sorted lists.
//    
//    /// Връща порция от IDs, вече филтрирани по текст и изключени елементи, в подредба по нутриент.
//    static func pagedIDs(
//        from ranks: [FoodRank],
//        matching needle: String,               // вече normalized (folded)
//        excluding excluded: Set<Int>,
//        offset: Int,
//        limit: Int
//    ) -> [Int] {
//        let seq = ranks.lazy
//            .filter { !excluded.contains($0.foodID) }
//            .filter {
//                // If there's no search text, include all items.
//                if needle.isEmpty { return true }
//                // Otherwise, simply check if the normalized name contains the search term.
//                return $0.nameKey.contains(needle)
//            }
//            .dropFirst(offset)
//            .prefix(limit)
//        return Array(seq.map(\.foodID))
//    }
//    // ----- END OF CORRECTION -----
//    
//    // This enum is no longer needed for the simplified nutrient search
//    // but might be used elsewhere. It's safe to keep.
//    enum TextPhase { case startsWith, contains }
//}
