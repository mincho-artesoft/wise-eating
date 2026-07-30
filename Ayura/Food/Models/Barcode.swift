import Foundation
import SwiftData

@Model
final class ProductBucket {
    /// The first GTIN in this bucket, stored as a number for correct sorting and querying.
    @Attribute(.unique) var bucketKey: Int64
    
    /// The Base64 encoded, zlib-compressed string containing all product data for this bucket.
    var compressedData: String
    
    init(bucketKey: Int64, compressedData: String) {
        self.bucketKey = bucketKey
        self.compressedData = compressedData
    }
}

import Foundation
import SwiftData

@Model
final class VocabularyEntry {
    @Attribute(.unique) var id: Int
    var word: String
    
    init(id: Int, word: String) {
        self.id = id
        self.word = word
    }
}
