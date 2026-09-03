import Foundation

struct BarcodeFoodSearchMatch {
    let food: FoodItem
    let confidence: Double
}

extension SmartFoodSearch3 {
    /// Finds several candidates through the existing indexed search and then
    /// applies the conservative barcode-specific scorer. FoodItem UUIDs remain
    /// the only identities crossing the search/matching boundary.
    @MainActor
    func searchFoodForBarcode(productName: String) async -> BarcodeFoodSearchMatch? {
        let variants = BarcodeFoodMatchScorer.queryVariants(for: productName)
        guard !variants.isEmpty else { return nil }

        let resultLimit = 30
        var foodsByID: [UUID: (food: FoodItem, relevance: Double)] = [:]
        for (variantIndex, query) in variants.enumerated() {
            let results = await searchResults(
                query: query,
                activeFilters: [],
                searchMode: nil,
                limit: resultLimit
            )
            let variantWeight = max(0.82, 1 - Double(variantIndex) * 0.06)
            // Keep the full edible FoodItem coverage of the previous barcode
            // flow. The current catalogue also contains seeded recipes and
            // other newer foods that can be the best packaged-product match.
            for (rank, food) in results.enumerated() where food.isEdible {
                let rankWeight = 1 - Double(rank) / Double(resultLimit)
                let relevance = max(0, rankWeight * variantWeight)
                if relevance > (foodsByID[food.id]?.relevance ?? -1) {
                    foodsByID[food.id] = (food, relevance)
                }
            }
        }

        let candidates = foodsByID.values.map {
            BarcodeFoodMatchCandidate(
                id: $0.food.id,
                name: $0.food.name,
                searchRelevance: $0.relevance
            )
        }
        guard let decision = BarcodeFoodMatchScorer.select(
            productName: productName,
            candidates: candidates
        ), let food = foodsByID[decision.foodID]?.food else {
            return nil
        }
        return BarcodeFoodSearchMatch(food: food, confidence: decision.confidence)
    }
}
