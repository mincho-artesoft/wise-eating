import Foundation

/// Everything the search engine keeps in memory, in one value.
struct SearchIndexSnapshot: Equatable {
    var compactFoods: [CompactFoodItem]
    var invertedIndex: [String: Set<UUID>]
    var vocabulary: [String]
    var maxNutrientValues: [NutrientType: Double]
    var nutrientRankings: [NutrientType: [UUID]]
    var ayurvedaFacetIndex: [String: Set<UUID>]
}

/// A compact binary form of the search index, to replace the JSON payload of
/// `SearchIndexCache` (69 MB for the bundled catalogue, mostly UUIDs spelled
/// out as text).
///
/// Every string is stored once in a table and referred to by number; a food
/// is referred to by its position in the food list instead of its UUID; the
/// Ayurveda metadata, which thousands of foods share, is stored once per
/// distinct value. The result is DEFLATE-compressed. Decoding gives back
/// exactly the snapshot that was encoded, so search results cannot change.
///
/// ayurveda-data/search_index_binary.py reads and writes the same format for
/// the catalogue build; the two must change together.
enum SearchIndexBinary {
    static let magic: [UInt8] = Array("AYSI".utf8)
    static let formatVersion: UInt8 = 1

    enum DecodingError: Error {
        case notASearchIndex
        case unsupportedVersion(UInt8)
        case truncated
        case corrupt(String)
    }

    // MARK: Encoding

    static func encode(_ snapshot: SearchIndexSnapshot) throws -> Data {
        var strings = StringTable()
        var body = Writer()

        // Ayurveda metadata: distinct values, as one JSON array.
        var metadataIndex: [AyurvedaCanonicalSearchMetadata: Int] = [:]
        var metadataList: [AyurvedaCanonicalSearchMetadata] = []
        for food in snapshot.compactFoods {
            if let metadata = food.ayurvedaMetadata, metadataIndex[metadata] == nil {
                metadataIndex[metadata] = metadataList.count
                metadataList.append(metadata)
            }
        }
        let metadataJSON = try JSONEncoder().encode(metadataList)
        body.varint(metadataJSON.count)
        body.bytes.append(contentsOf: metadataJSON)

        var ordinal: [UUID: Int] = [:]
        ordinal.reserveCapacity(snapshot.compactFoods.count)
        body.varint(snapshot.compactFoods.count)
        for (position, food) in snapshot.compactFoods.enumerated() {
            ordinal[food.id] = position
            body.uuid(food.id)
            body.varint(strings.index(of: food.name))
            body.stringSet(food.searchTokens, &strings)
            body.varint(food.minAgeMonths)
            body.varint(food.enforcedMinAgeMonths.map { $0 + 1 } ?? 0)
            body.stringSet(food.allergens, &strings)
            body.double(food.ph)
            body.double(food.referenceWeightG)
            body.bytes.append(
                (food.isRecipe ? 1 : 0) | (food.isMenu ? 2 : 0)
                    | (food.isFavorite ? 4 : 0) | (food.isEdible ? 8 : 0)
            )
            body.stringSet(food.ayurvedaFacets, &strings)
            body.varint(food.ayurvedaMetadata.flatMap { metadataIndex[$0] }.map { $0 + 1 } ?? 0)
            body.varint(food.nutrientValues.count)
            for (nutrient, value) in food.nutrientValues.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                body.varint(strings.index(of: nutrient.rawValue))
                body.double(value)
            }
        }
        guard ordinal.count == snapshot.compactFoods.count else {
            throw DecodingError.corrupt("duplicate food id")
        }

        func postings(_ index: [String: Set<UUID>]) throws {
            body.varint(index.count)
            for (key, ids) in index.sorted(by: { $0.key < $1.key }) {
                body.varint(strings.index(of: key))
                let positions = try ids.map { id -> Int in
                    guard let position = ordinal[id] else {
                        throw DecodingError.corrupt("index refers to an unknown food")
                    }
                    return position
                }.sorted()
                body.varint(positions.count)
                var previous = 0
                for position in positions {
                    body.varint(position - previous)
                    previous = position
                }
            }
        }
        try postings(snapshot.invertedIndex)
        try postings(snapshot.ayurvedaFacetIndex)

        body.varint(snapshot.vocabulary.count)
        for word in snapshot.vocabulary { body.varint(strings.index(of: word)) }

        body.varint(snapshot.maxNutrientValues.count)
        for (nutrient, value) in snapshot.maxNutrientValues.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            body.varint(strings.index(of: nutrient.rawValue))
            body.double(value)
        }

        // Rankings keep their order: it is the sort the engine relies on.
        body.varint(snapshot.nutrientRankings.count)
        for (nutrient, ids) in snapshot.nutrientRankings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            body.varint(strings.index(of: nutrient.rawValue))
            body.varint(ids.count)
            for id in ids {
                guard let position = ordinal[id] else {
                    throw DecodingError.corrupt("ranking refers to an unknown food")
                }
                body.varint(position)
            }
        }

        var out = Writer()
        out.varint(strings.list.count)
        for string in strings.list {
            let utf8 = Array(string.utf8)
            out.varint(utf8.count)
            out.bytes.append(contentsOf: utf8)
        }
        out.bytes.append(contentsOf: body.bytes)

        let packed = try (Data(out.bytes) as NSData).compressed(using: .zlib) as Data
        var file = Data(magic)
        file.append(formatVersion)
        file.append(packed)
        return file
    }

    // MARK: Decoding

    static func decode(_ data: Data) throws -> SearchIndexSnapshot {
        guard data.count > magic.count, Array(data.prefix(magic.count)) == magic else {
            throw DecodingError.notASearchIndex
        }
        let version = data[data.startIndex + magic.count]
        guard version == formatVersion else { throw DecodingError.unsupportedVersion(version) }
        let packed = data.dropFirst(magic.count + 1)
        let raw = try (Data(packed) as NSData).decompressed(using: .zlib) as Data
        var reader = Reader(bytes: [UInt8](raw))

        let stringCount = try reader.varint()
        var strings: [String] = []
        strings.reserveCapacity(stringCount)
        for _ in 0..<stringCount {
            strings.append(try reader.string(length: try reader.varint()))
        }
        func string() throws -> String {
            let index = try reader.varint()
            guard index < strings.count else { throw DecodingError.corrupt("string index") }
            return strings[index]
        }
        func stringSet() throws -> Set<String> {
            let count = try reader.varint()
            var out = Set<String>(minimumCapacity: count)
            for _ in 0..<count { out.insert(try string()) }
            return out
        }
        func nutrient() throws -> NutrientType {
            let name = try string()
            guard let nutrient = NutrientType(rawValue: name) else {
                throw DecodingError.corrupt("unknown nutrient \(name)")
            }
            return nutrient
        }

        let metadataLength = try reader.varint()
        let metadataList = try JSONDecoder().decode(
            [AyurvedaCanonicalSearchMetadata].self,
            from: Data(try reader.take(metadataLength))
        )

        let foodCount = try reader.varint()
        var foods: [CompactFoodItem] = []
        foods.reserveCapacity(foodCount)
        for _ in 0..<foodCount {
            let id = try reader.uuid()
            let name = try string()
            let tokens = try stringSet()
            let minAge = try reader.varint()
            let enforced = try reader.varint()
            let allergens = try stringSet()
            let ph = try reader.double()
            let weight = try reader.double()
            let flags = try reader.byte()
            let facets = try stringSet()
            let metadataRef = try reader.varint()
            guard metadataRef <= metadataList.count else { throw DecodingError.corrupt("metadata index") }
            let nutrientCount = try reader.varint()
            var nutrients: [NutrientType: Double] = [:]
            nutrients.reserveCapacity(nutrientCount)
            for _ in 0..<nutrientCount {
                let key = try nutrient()
                nutrients[key] = try reader.double()
            }
            foods.append(CompactFoodItem(
                id: id,
                name: name,
                searchTokens: tokens,
                minAgeMonths: minAge,
                enforcedMinAgeMonths: enforced == 0 ? nil : enforced - 1,
                allergens: allergens,
                ph: ph,
                referenceWeightG: weight,
                isRecipe: flags & 1 != 0,
                isMenu: flags & 2 != 0,
                isFavorite: flags & 4 != 0,
                isEdible: flags & 8 != 0,
                ayurvedaFacets: facets,
                ayurvedaMetadata: metadataRef == 0 ? nil : metadataList[metadataRef - 1],
                nutrientValues: nutrients
            ))
        }

        func food(at position: Int) throws -> UUID {
            guard position < foods.count else { throw DecodingError.corrupt("food position") }
            return foods[position].id
        }
        func postings() throws -> [String: Set<UUID>] {
            let count = try reader.varint()
            var out: [String: Set<UUID>] = [:]
            out.reserveCapacity(count)
            for _ in 0..<count {
                let key = try string()
                let size = try reader.varint()
                var ids = Set<UUID>(minimumCapacity: size)
                var position = 0
                for _ in 0..<size {
                    position += try reader.varint()
                    ids.insert(try food(at: position))
                }
                out[key] = ids
            }
            return out
        }
        let inverted = try postings()
        let facetIndex = try postings()

        let vocabularyCount = try reader.varint()
        var vocabulary: [String] = []
        vocabulary.reserveCapacity(vocabularyCount)
        for _ in 0..<vocabularyCount { vocabulary.append(try string()) }

        var maxValues: [NutrientType: Double] = [:]
        for _ in 0..<(try reader.varint()) {
            let key = try nutrient()
            maxValues[key] = try reader.double()
        }

        var rankings: [NutrientType: [UUID]] = [:]
        for _ in 0..<(try reader.varint()) {
            let key = try nutrient()
            let size = try reader.varint()
            var ids: [UUID] = []
            ids.reserveCapacity(size)
            for _ in 0..<size { ids.append(try food(at: try reader.varint())) }
            rankings[key] = ids
        }
        guard reader.isAtEnd else { throw DecodingError.corrupt("trailing bytes") }

        return SearchIndexSnapshot(
            compactFoods: foods,
            invertedIndex: inverted,
            vocabulary: vocabulary,
            maxNutrientValues: maxValues,
            nutrientRankings: rankings,
            ayurvedaFacetIndex: facetIndex
        )
    }

    // MARK: Plumbing

    private struct StringTable {
        var list: [String] = []
        private var positions: [String: Int] = [:]

        mutating func index(of string: String) -> Int {
            if let known = positions[string] { return known }
            positions[string] = list.count
            list.append(string)
            return list.count - 1
        }
    }

    private struct Writer {
        var bytes: [UInt8] = []

        mutating func varint(_ value: Int) {
            precondition(value >= 0)
            var rest = UInt64(value)
            while rest >= 0x80 {
                bytes.append(UInt8(rest & 0x7F) | 0x80)
                rest >>= 7
            }
            bytes.append(UInt8(rest))
        }

        mutating func double(_ value: Double) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func uuid(_ value: UUID) {
            withUnsafeBytes(of: value.uuid) { bytes.append(contentsOf: $0) }
        }

        mutating func stringSet(_ set: Set<String>, _ strings: inout StringTable) {
            varint(set.count)
            for string in set.sorted() { varint(strings.index(of: string)) }
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var isAtEnd: Bool { offset == bytes.count }

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw DecodingError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, offset + count <= bytes.count else { throw DecodingError.truncated }
            defer { offset += count }
            return bytes[offset..<(offset + count)]
        }

        mutating func varint() throws -> Int {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let next = try byte()
                value |= UInt64(next & 0x7F) << shift
                if next & 0x80 == 0 { break }
                shift += 7
                guard shift < 64 else { throw DecodingError.corrupt("varint") }
            }
            guard let result = Int(exactly: value) else { throw DecodingError.corrupt("varint") }
            return result
        }

        mutating func double() throws -> Double {
            let slice = try take(8)
            var pattern: UInt64 = 0
            for (index, byte) in slice.enumerated() { pattern |= UInt64(byte) << UInt64(8 * index) }
            return Double(bitPattern: pattern)
        }

        mutating func uuid() throws -> UUID {
            let b = Array(try take(16))
            return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                               b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        }

        mutating func string(length: Int) throws -> String {
            String(decoding: try take(length), as: UTF8.self)
        }
    }
}
