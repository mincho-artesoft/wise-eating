import Foundation
import SwiftData

@MainActor
final class ProductDataManager {
    
    static let shared = ProductDataManager()
    
    private let modelContext: ModelContext
    private let userDefaultsKey = "isDatabaseSeeden_v2" // Changed key to force re-seed if needed
    
    // --- CHANGE 1: The in-memory vocabulary cache is REMOVED ---
    // private var vocabulary: [Int: String] = [:]
    // -----------------------------------------------------------
    
    private var bucketCache = NSCache<NSString, NSDictionary>()

    private init() {
        self.modelContext = GlobalState.modelContext!
    }
    
   
    // -------------------------------------------------------------
    
    // --- CHANGE 4: This function is now ASYNC ---
    public func findProductName(for gtin: String) async -> String? {
        let candidates = Self.lookupCandidates(for: gtin)
        guard !candidates.isEmpty,
              let buckets = try? modelContext.fetch(FetchDescriptor<ProductBucket>())
        else {
            print("DEBUG: Could not find any bucket for GTIN \(gtin).")
            return nil
        }

        for candidate in candidates {
            let normalizedCandidate = Self.normalizedDecimal(candidate)
            guard let bucket = buckets
                .filter({
                    Self.compareDecimal($0.bucketKey, normalizedCandidate)
                        != .orderedDescending
                })
                .max(by: {
                    Self.compareDecimal($0.bucketKey, $1.bucketKey)
                        == .orderedAscending
                })
            else {
                continue
            }
            guard let tokenIDs = getTokenIDs(for: candidate, from: bucket) else {
                continue
            }
            return await reconstructName(from: tokenIDs)
        }

        print("DEBUG: No local product found for GTIN candidates \(candidates).")
        return nil
    }

    /// OFF stores most UPC-A values in their zero-prefixed EAN-13 form, while
    /// AVFoundation can return the 12-digit UPC-A printed on the package. GS1
    /// payloads similarly carry a 14-digit, zero-prefixed GTIN. Try the exact
    /// scan first, followed by equivalent zero-prefix representations.
    private static func lookupCandidates(for value: String) -> [String] {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber) else { return [] }

        var result: [String] = []
        func append(_ candidate: String) {
            guard !candidate.isEmpty, !result.contains(candidate) else { return }
            result.append(candidate)
        }

        append(raw)
        switch raw.count {
        case 12:
            append("0" + raw)
        case 13 where raw.first == "0":
            append(String(raw.dropFirst()))
        case 14 where raw.first == "0":
            let gtin13 = String(raw.dropFirst())
            append(gtin13)
            if gtin13.first == "0" {
                append(String(gtin13.dropFirst()))
            }
        default:
            break
        }
        return result
    }

    private static func normalizedDecimal(_ value: String) -> String {
        guard value.allSatisfy(\.isNumber) else { return "" }
        let trimmed = value.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private static func compareDecimal(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedDecimal(lhs)
        let right = normalizedDecimal(rhs)
        if left.count != right.count {
            return left.count < right.count ? .orderedAscending : .orderedDescending
        }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
    
    private func getTokenIDs(for gtin: String, from bucket: ProductBucket) -> [Int]? {
        // ... (This function is correct and does not need changes) ...
        let cacheKey = String(bucket.bucketKey) as NSString
        if let cachedBucket = bucketCache.object(forKey: cacheKey) as? [String: [Int]],
           let tokenIDs = cachedBucket[gtin] {
            return tokenIDs
        }

        guard let compressedData = Data(base64Encoded: bucket.compressedData),
              let decompressedData = try? ZlibGzip.decompress(data: compressedData) else {
            print("DEBUG ERROR: Failed to decompress data using ZlibGzip for bucket \(bucket.bucketKey).")
            return nil
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: decompressedData, options: []),
              let bucketContent = jsonObject as? [String: [Int]] else {
            print("DEBUG ERROR: Failed to decode the resulting JSON for bucket \(bucket.bucketKey).")
            return nil
        }
        
        if bucketContent[gtin] == nil {
             print("DEBUG ERROR: JSON decoded, but key '\(gtin)' not found in dictionary.")
        }
        
        bucketCache.setObject(bucketContent as NSDictionary, forKey: cacheKey)
        return bucketContent[gtin]
    }

    func resetCatalogCache() {
        bucketCache.removeAllObjects()
    }
    
    // --- CHANGE 5: The ENTIRE reconstructName function is REWRITTEN ---
    /// Reconstructs a product name by fetching the required words directly from SwiftData.
    private func reconstructName(from tokenIDs: [Int]) async -> String? {
        guard !tokenIDs.isEmpty else { return "" }
        
        // 1. Create a predicate to fetch all vocabulary entries whose ID is in our list.
        // This is ONE efficient database query.
        let predicate = #Predicate<VocabularyEntry> { tokenIDs.contains($0.tokenIndex) }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        do {
            // 2. Execute the fetch.
            let entries = try modelContext.fetch(descriptor)
            
            // 3. The fetch returns an unordered array. We must convert it to a dictionary
            // to reassemble the words in the correct order.
            let wordMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.tokenIndex, $0.word) })
            
            // 4. Reconstruct the final string using the original tokenID order.
            let words = tokenIDs.compactMap { wordMap[$0] }
            return words.joined()
            
        } catch {
            print("DEBUG ERROR: Failed to fetch words from vocabulary database: \(error)")
            return nil
        }
    }
}
