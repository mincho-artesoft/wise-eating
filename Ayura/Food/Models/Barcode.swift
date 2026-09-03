import Foundation
import SwiftData

@Model
final class ProductBucket {
    @Attribute(.unique) var id: UUID

    /// The first GTIN in this bucket. It remains a catalog key, not identity.
    /// A decimal string is used because a small part of the source exceeds Int64.
    @Attribute(.unique) var bucketKey: String
    
    /// The Base64 encoded, zlib-compressed string containing all product data for this bucket.
    var compressedData: String
    
    init(id: UUID = UUID(), bucketKey: String, compressedData: String) {
        self.id = id
        self.bucketKey = bucketKey
        self.compressedData = compressedData
    }
}

import Foundation
import SwiftData

@Model
final class VocabularyEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var tokenIndex: Int
    var word: String
    
    init(id: UUID = UUID(), tokenIndex: Int, word: String) {
        self.id = id
        self.tokenIndex = tokenIndex
        self.word = word
    }
}
