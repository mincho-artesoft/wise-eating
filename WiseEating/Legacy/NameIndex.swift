//import Foundation
//import SwiftData
//
//public struct NameEntry: Codable, Hashable {
//    public let foodID: Int
//    public let nameKey: String // lowercased + без диакритика (== FoodItem.nameNormalized)
//}
//
//@Model
//final class NameIndex {
//    // един ред с ключ "ALL"
//    @Attribute(.unique)
//    var key: String
//
//    var entriesData: Data?
//
//    var entries: [NameEntry] {
//        get {
//            guard let d = entriesData,
//                  let e = try? JSONDecoder().decode([NameEntry].self, from: d) else { return [] }
//            return e
//        }
//        set { entriesData = try? JSONEncoder().encode(newValue) }
//    }
//
//    init(entries: [NameEntry]) {
//        self.key = "ALL"
//        self.entries = entries
//    }
//}
