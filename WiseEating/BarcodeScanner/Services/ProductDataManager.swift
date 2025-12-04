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
        guard let gtinAsInt = Int64(gtin) else { return nil }
    
        let predicate = #Predicate<ProductBucket> { $0.bucketKey <= gtinAsInt }
        var fetchDescriptor = FetchDescriptor<ProductBucket>(predicate: predicate, sortBy: [SortDescriptor(\.bucketKey, order: .reverse)])
        fetchDescriptor.fetchLimit = 1

        guard let bucket = try? modelContext.fetch(fetchDescriptor).first else {
            print("DEBUG: Could not find any bucket for GTIN \(gtin).")
            return nil
        }
        
        print("DEBUG: Found bucket with key \(bucket.bucketKey) for target GTIN \(gtin).")

        guard let tokenIDs = getTokenIDs(for: gtin, from: bucket) else {
            return nil
        }
        
        // The call to reconstructName is now awaited
        return await reconstructName(from: tokenIDs)
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
    
    // --- CHANGE 5: The ENTIRE reconstructName function is REWRITTEN ---
    /// Reconstructs a product name by fetching the required words directly from SwiftData.
    private func reconstructName(from tokenIDs: [Int]) async -> String? {
        guard !tokenIDs.isEmpty else { return "" }
        
        // 1. Create a predicate to fetch all vocabulary entries whose ID is in our list.
        // This is ONE efficient database query.
        let predicate = #Predicate<VocabularyEntry> { tokenIDs.contains($0.id) }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        do {
            // 2. Execute the fetch.
            let entries = try modelContext.fetch(descriptor)
            
            // 3. The fetch returns an unordered array. We must convert it to a dictionary
            // to reassemble the words in the correct order.
            let wordMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.word) })
            
            // 4. Reconstruct the final string using the original tokenID order.
            let words = tokenIDs.compactMap { wordMap[$0] }
            return words.joined()
            
        } catch {
            print("DEBUG ERROR: Failed to fetch words from vocabulary database: \(error)")
            return nil
        }
    }
}
