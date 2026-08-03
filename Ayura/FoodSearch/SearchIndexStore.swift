import Foundation
import SwiftData

@MainActor
final class SearchIndexStore {
    static let shared = SearchIndexStore()

    /// Bump this when the structure of CompactFoodItem / tokens changes
    private let currentIndexVersion: Int = 9

    // MARK: - In-Memory Cache
    private(set) var revision: UInt64 = 0
    private(set) var compactFoods: [CompactFoodItem] = []
    private(set) var compactMap: [Int: CompactFoodItem] = [:]
    private(set) var invertedIndex: [String: Set<Int>] = [:]
    private(set) var vocabulary: [String] = []
    private(set) var maxNutrientValues: [NutrientType: Double] = [:]
    private(set) var nutrientRankings: [NutrientType: [Int]] = [:]
    private(set) var ayurvedaFacetIndex: [String: Set<Int>] = [:]
    private var bundledAyurvedaSearchMap: [Int: AyurvedaCanonicalSearchMetadata]?

    // MARK: - Async Save Infra
    /// Таймер за debounce на тежкия запис на кеша
    private var saveDebounceTimer: Timer?

    private init() {}

    // MARK: - 1. Public Setup & Smart Rebuild

    /// Проверява дали индекса е актуален и го преизгражда само ако се налага.
    func rebuildIndexIfNeeded(context: ModelContext, force: Bool = false) throws {
        // 1. Взимаме текущия брой храни в базата
        let currentFoodCount = try context.fetchCount(FetchDescriptor<FoodItem>())
        
        // 2. Ако НЕ е насилствено (force), правим проверка
        if !force {
            let cacheDescriptor = FetchDescriptor<SearchIndexCache>(predicate: #Predicate { $0.key == "main" })
            
            if let existingCache = try context.fetch(cacheDescriptor).first {
                if existingCache.version == currentIndexVersion {
                    if existingCache.foodsCount == currentFoodCount {
                        print("✅ SearchIndexStore: Index is up-to-date (version: \(existingCache.version), DB: \(currentFoodCount)). Skipping rebuild.")
                        return
                    } else {
                        print("⚠️ SearchIndexStore: Index outdated (Cache: \(existingCache.foodsCount), DB: \(currentFoodCount)). Rebuilding...")
                    }
                } else {
                    print("⚠️ SearchIndexStore: Index version mismatch (cache: \(existingCache.version), expected: \(currentIndexVersion)). Rebuilding...")
                }
            } else {
                print("⚠️ SearchIndexStore: No index cache found. Building fresh...")
            }
        } else {
            print("Force rebuild requested.")
        }
        
        // === СЪЩИНСКО ИЗГРАЖДАНЕ ===
        print("🔎 SearchIndexStore: Starting full index build...")
        
        // Извличаме само храните. Вече не ни трябва NutrientIndex.
        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let canonicalMap = try ayurvedaSearchMap(context: context)
        
        buildInMemory(foods: foods, canonicalMap: canonicalMap)
        try saveCache(context: context)
        
        print("🔎 SearchIndexStore: Index build complete & saved (\(foods.count) items).")
    }
    
    func ensureLoaded(container: ModelContainer) async {
        if !compactFoods.isEmpty { return }

        let ctx = ModelContext(container)

        do {
            let cacheDescriptor = FetchDescriptor<SearchIndexCache>(
                predicate: #Predicate { $0.key == "main" }
            )
            if let cache = try ctx.fetch(cacheDescriptor).first {
                if cache.version == currentIndexVersion {
                    if let payload = try? JSONDecoder().decode(SearchIndexPayload.self, from: cache.payloadData) {
                        apply(payload: payload)
                        print("🔎 SearchIndexStore: Loaded from cached index (version: \(cache.version), \(compactFoods.count) foods).")
                        return
                    } else {
                        print("⚠️ SearchIndexStore: Cache decode failed. Forcing rebuild...")
                    }
                } else {
                    print("⚠️ SearchIndexStore: Cached index version (\(cache.version)) != expected (\(currentIndexVersion)). Forcing rebuild...")
                }
            }
        } catch {
            print("⚠️ SearchIndexStore: Failed to fetch cache: \(error)")
        }

        print("🔎 SearchIndexStore: No valid cache found. Rebuilding...")
        try? forceRebuild(context: ctx)
    }

    // MARK: - 2. Force Rebuild

    func forceRebuild(context: ModelContext) throws {
        print("🔎 SearchIndexStore: Starting full index rebuild...")

        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let canonicalMap = try ayurvedaSearchMap(context: context)
        // Премахнато извличането на NutrientIndex
        
        buildInMemory(foods: foods, canonicalMap: canonicalMap)

        try saveCache(context: context)
        
        print("🔎 SearchIndexStore: Full rebuild complete. Indexed \(foods.count) items.")
    }

    // MARK: - 3. CRUD & Status Operations
    // ... (без промяна в updateFavoriteStatus, updateItem, removeItem, scheduleCacheSave) ...

    func updateFavoriteStatus(for foodID: Int, isFavorite: Bool) {
        guard let item = compactMap[foodID],
              item.isFavorite != isFavorite else {
            return
        }
        let updated = CompactFoodItem(
            id: item.id, name: item.name, searchTokens: item.searchTokens,
            minAgeMonths: item.minAgeMonths,
            enforcedMinAgeMonths: item.enforcedMinAgeMonths,
            allergens: item.allergens,
            ph: item.ph, referenceWeightG: item.referenceWeightG,
            isRecipe: item.isRecipe, isMenu: item.isMenu, isFavorite: isFavorite,
            ayurvedaFacets: item.ayurvedaFacets,
            ayurvedaMetadata: item.ayurvedaMetadata,
            nutrientValues: item.nutrientValues
        )
        compactMap[foodID] = updated
        if let index = compactFoods.firstIndex(where: { $0.id == foodID }) {
            compactFoods[index] = updated
        }
        revision &+= 1
        if let context = GlobalState.modelContext {
             scheduleCacheSave(context: context)
        }
    }
    
    func updateItem(_ food: FoodItem, context: ModelContext) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // An incremental update cannot safely start from an empty store because
        // it would produce a cache containing only the newly-saved item.
        if compactFoods.isEmpty {
            do {
                try forceRebuild(context: context)
                return
            } catch {
                print("⚠️ SearchIndexStore: Full rebuild before update failed: \(error)")
            }
        }

        guard let oldCompactItem = compactMap[food.id] else {
            let metadata = ayurvedaSearchMetadata(
                foodID: food.id,
                context: context
            )
            let newCompactItem = makeCompactItem(
                from: food,
                ayurvedaMetadata: metadata,
                enforcedMinAgeMonths: metadata?.enforcedMinAgeMonths
            )
            for token in newCompactItem.searchTokens {
                invertedIndex[token, default: []].insert(newCompactItem.id)
                if !vocabulary.contains(token) { vocabulary.append(token) }
            }
            compactFoods.append(newCompactItem)
            compactMap[newCompactItem.id] = newCompactItem
            for facet in newCompactItem.ayurvedaFacets {
                ayurvedaFacetIndex[facet, default: []].insert(newCompactItem.id)
            }
            rebuildNutrientIndexes(for: Set(newCompactItem.nutrientValues.keys))
            revision &+= 1
            scheduleCacheSave(context: context)
            print("🔎 SearchIndexStore: Inserted new item '\(food.name)' during update call.")
            return
        }

        // Rebuild the compact item first so we can compare searchTokens,
        // which already include any exclusion rules.
        let refreshedMetadata = ayurvedaSearchMetadata(
            foodID: food.id,
            context: context
        )
        let newCompactItem = makeCompactItem(
            from: food,
            ayurvedaMetadata: refreshedMetadata,
            enforcedMinAgeMonths: refreshedMetadata?.enforcedMinAgeMonths
                ?? oldCompactItem.enforcedMinAgeMonths
        )

        let oldTokens = oldCompactItem.searchTokens
        let newTokens = newCompactItem.searchTokens

        let tokensToRemove = oldTokens.subtracting(newTokens)
        let tokensToAdd = newTokens.subtracting(oldTokens)
        let facetsToRemove = oldCompactItem.ayurvedaFacets
            .subtracting(newCompactItem.ayurvedaFacets)
        let facetsToAdd = newCompactItem.ayurvedaFacets
            .subtracting(oldCompactItem.ayurvedaFacets)

        for token in tokensToRemove {
            invertedIndex[token]?.remove(food.id)
            if invertedIndex[token]?.isEmpty == true {
                invertedIndex.removeValue(forKey: token)
                vocabulary.removeAll { $0 == token }
            }
        }
        for token in tokensToAdd {
            invertedIndex[token, default: []].insert(food.id)
            if !vocabulary.contains(token) {
                vocabulary.append(token)
            }
        }
        for facet in facetsToRemove {
            ayurvedaFacetIndex[facet]?.remove(food.id)
            if ayurvedaFacetIndex[facet]?.isEmpty == true {
                ayurvedaFacetIndex.removeValue(forKey: facet)
            }
        }
        for facet in facetsToAdd {
            ayurvedaFacetIndex[facet, default: []].insert(food.id)
        }

        if let idx = compactFoods.firstIndex(where: { $0.id == newCompactItem.id }) {
            compactFoods[idx] = newCompactItem
        } else {
            compactFoods.append(newCompactItem)
        }
        compactMap[newCompactItem.id] = newCompactItem

        rebuildNutrientIndexes(
            for: Set(oldCompactItem.nutrientValues.keys)
                .union(newCompactItem.nutrientValues.keys)
        )
        revision &+= 1
        scheduleCacheSave(context: context)
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("🔎 SearchIndexStore (Explicit): Updated item '\(food.name)' in \(String(format: "%.4f", timeElapsed * 1000)) ms.")
    }

    func removeItem(id: Int, context: ModelContext) {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let compact = compactMap[id] else { return }
        let tokens = compact.searchTokens
        let facets = compact.ayurvedaFacets

        compactFoods.removeAll { $0.id == id }
        compactMap.removeValue(forKey: id)

        for token in tokens {
            guard var ids = invertedIndex[token] else { continue }
            ids.remove(id)
            if ids.isEmpty {
                invertedIndex.removeValue(forKey: token)
                vocabulary.removeAll { $0 == token }
            } else {
                invertedIndex[token] = ids
            }
        }
        for facet in facets {
            ayurvedaFacetIndex[facet]?.remove(id)
            if ayurvedaFacetIndex[facet]?.isEmpty == true {
                ayurvedaFacetIndex.removeValue(forKey: facet)
            }
        }

        rebuildNutrientIndexes(for: Set(compact.nutrientValues.keys))
        revision &+= 1
        scheduleCacheSave(context: context)
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("🔎 SearchIndexStore: Removed item ID \(id) in \(String(format: "%.4f", timeElapsed * 1000)) ms (in-memory only, save debounced).")
    }

    private func scheduleCacheSave(context: ModelContext) {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            let start = CFAbsoluteTimeGetCurrent()
            do {
                try self.saveCache(context: context)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                print("💾 SearchIndexStore: Debounced cache saved in \(String(format: "%.4f", elapsed * 1000)) ms.")
            } catch {
                print("⚠️ SearchIndexStore: Failed to save cache: \(error)")
            }
        }
    }

    // MARK: - Private Logic

    /// ✅ ПРОМЯНА: Премахнахме `nutrientIndexes`.
    /// Сега `tmpRankings` се генерира динамично от `tmpFoods`.
    private func buildInMemory(
        foods: [FoodItem],
        canonicalMap: [Int: AyurvedaCanonicalSearchMetadata]
    ) {
        var tmpFoods: [CompactFoodItem] = []
        var tmpMap: [Int: CompactFoodItem] = [:]
        var tmpInverted: [String: Set<Int>] = [:]
        var vocabSet = Set<String>()
        var tmpFacetIndex: [String: Set<Int>] = [:]

        // 1. Build Compact Items & Index
        for food in foods {
            let canonical = canonicalMap[food.id]
            let compact = makeCompactItem(
                from: food,
                ayurvedaMetadata: canonical,
                enforcedMinAgeMonths: canonical?.enforcedMinAgeMonths
            )
            tmpFoods.append(compact)
            tmpMap[compact.id] = compact

            for t in compact.searchTokens {
                tmpInverted[t, default: []].insert(compact.id)
                vocabSet.insert(t)
            }
            
            for facet in compact.ayurvedaFacets {
                tmpFacetIndex[facet, default: []].insert(compact.id)
            }
        }

        // 2. Calculate Max Values & Rankings on the fly
        var tmpMaxValues: [NutrientType: Double] = [:]
        var tmpRankings: [NutrientType: [Int]] = [:]

        // Итерираме през всички известни нутриенти
        for nutrient in NutrientType.allCases {
            // Събираме двойки (ID, стойност_на_100г) само за тези, които имат стойност > 0
            let itemsWithValues = tmpFoods.compactMap { item -> (Int, Double)? in
                guard let rawVal = item.nutrientValues[nutrient], rawVal > 0 else { return nil }
                let ref = item.referenceWeightG
                guard ref > 0 else { return nil }
                
                let density = (rawVal / ref) * 100.0
                return (item.id, density)
            }
            
            // За maxValues - просто максималната плътност
            if let maxDensity = itemsWithValues.map({ $0.1 }).max() {
                tmpMaxValues[nutrient] = maxDensity
            }
            
            // За Rankings - сортираме по плътност низходящо и взимаме само ID-тата
            let sortedIDs = itemsWithValues
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            
            if !sortedIDs.isEmpty {
                tmpRankings[nutrient] = sortedIDs
            }
        }

        self.compactFoods = tmpFoods
        self.compactMap = tmpMap
        self.invertedIndex = tmpInverted
        self.vocabulary = Array(vocabSet)
        self.maxNutrientValues = tmpMaxValues
        self.nutrientRankings = tmpRankings
        self.ayurvedaFacetIndex = tmpFacetIndex
        revision &+= 1
    }

    private func saveCache(context: ModelContext) throws {
        let payload = SearchIndexPayload(
            compactFoods: compactFoods.map { $0.asCodable() },
            invertedIndex: invertedIndex.mapValues { Array($0) },
            vocabulary: vocabulary,
            maxNutrientValues: encodeMaxNutrientValues(maxNutrientValues),
            nutrientRankings: encodeNutrientRankings(nutrientRankings),
            ayurvedaFacetIndex: ayurvedaFacetIndex.mapValues { Array($0) }
        )

        let data = try JSONEncoder().encode(payload)
        try? context.delete(model: SearchIndexCache.self)

        let cache = SearchIndexCache(
            key: "main",
            payloadData: data,
            foodsCount: compactFoods.count,
            version: currentIndexVersion,
            createdAt: .now
        )
        context.insert(cache)
        try context.save()
    }

    private func apply(payload: SearchIndexPayload) {
        let compact = payload.compactFoods.map { CompactFoodItem($0) }
        
        self.compactFoods = compact
        self.compactMap = Dictionary(uniqueKeysWithValues: compact.map { ($0.id, $0) })
        self.invertedIndex = payload.invertedIndex.reduce(into: [:]) { dict, pair in
            dict[pair.key] = Set(pair.value)
        }
        self.vocabulary = payload.vocabulary
        self.maxNutrientValues = decodeMaxNutrientValues(payload.maxNutrientValues)
        self.nutrientRankings = decodeNutrientRankings(payload.nutrientRankings)
        self.ayurvedaFacetIndex = payload.ayurvedaFacetIndex.reduce(into: [:]) {
            $0[$1.key] = Set($1.value)
        }
        revision &+= 1
    }
    
    private func makeCompactItem(
        from food: FoodItem,
        ayurvedaMetadata: AyurvedaCanonicalSearchMetadata?,
        enforcedMinAgeMonths: Int? = nil
    ) -> CompactFoodItem {
        var tokenSet: Set<String>
        if !food.searchTokens.isEmpty {
            tokenSet = Set(food.searchTokens)
        } else if !food.searchTokens2.isEmpty {
            tokenSet = Set(food.searchTokens2)
        } else {
            tokenSet = Set(FoodItem.makeTokens(from: food.name))
        }

        // FIX: Remove tokens that appear after exclusion keywords in the food name.
        // Example: "chicken salad excluding tomato" should NOT index "tomato".
        let lowerName = food.name.lowercased()

        // Ensure "or" is indexed as a token if it appears in the name.
        // This supports literal phrase searches like "chicken or turkey".
        if lowerName.contains(" or ") {
            tokenSet.insert("or")
        }

        let exclusionKeywords = [" excluding ", " without ", " no ", " except "]

        for keyword in exclusionKeywords {
            if let range = lowerName.range(of: keyword) {
                // Part of the name AFTER the keyword, e.g. "tomato and carrots"
                let excludedPart = lowerName[range.upperBound...]
                let excludedTokens = FoodItem.makeTokens(from: String(excludedPart))

                // Remove these tokens from the search token set
                for excluded in excludedTokens {
                    tokenSet.remove(excluded)
                }
            }
        }

        let allergenNames = Set((food.allergens ?? []).map { $0.name })

        var nutrientDict: [NutrientType: Double] = [:]

        // Оптимизация: итерираме само нутриентите, които имат значение за търсенето.
        // Но NutrientType.allCases е приемливо бързо (~100 итерации).
        for nutrient in NutrientType.allCases {
            let val = food.calculatedValue(for: nutrient)
            if val > 0 {
                nutrientDict[nutrient] = val
            }
        }

        let phValue: Double = {
            if food.isRecipe || food.isMenu {
                return FoodItem.aggregatedNutrition(for: food).other?.alkalinityPH?.value ?? 0.0
            } else {
                return food.other?.alkalinityPH?.value ?? 0.0
            }
        }()

        let adjustedAyurveda: AyurvedaCanonicalSearchMetadata
        if let ayurvedaMetadata {
            adjustedAyurveda = ayurvedaMetadata
                .applyingDerivedModifiers(to: food.name)
        } else {
            // The estimate already includes name-based preparation modifiers.
            adjustedAyurveda = AyurvedaCanonicalSearchMetadata(
                estimate: AyurvedaRules.shared.estimated(
                    name: food.name
                ),
                enforcedMinAgeMonths: food.minAgeMonths
            )
        }

        return CompactFoodItem(
            id: food.id,
            name: food.name,
            searchTokens: tokenSet,
            minAgeMonths: food.minAgeMonths,
            enforcedMinAgeMonths: enforcedMinAgeMonths ?? food.minAgeMonths,
            allergens: allergenNames,
            ph: phValue,
            referenceWeightG: food.referenceWeightG,
            isRecipe: food.isRecipe,
            isMenu: food.isMenu,
            isFavorite: food.isFavorite,
            ayurvedaFacets: adjustedAyurveda.facets,
            ayurvedaMetadata: adjustedAyurveda,
            nutrientValues: nutrientDict
        )
    }

    private func bundledAyurvedaMap() throws
        -> [Int: AyurvedaCanonicalSearchMetadata] {
        if let bundledAyurvedaSearchMap {
            return bundledAyurvedaSearchMap
        }
        let map = try AyurvedaFacet.canonicalSearchMapFromBundledSeed()
        bundledAyurvedaSearchMap = map
        return map
    }

    /// Keeps all bundled/preseeded metadata and overlays profiles saved in the
    /// live database. A user-authored profile intentionally replaces the
    /// bundled metadata for that food while retaining its enforced seed age.
    private func ayurvedaSearchMap(
        context: ModelContext
    ) throws -> [Int: AyurvedaCanonicalSearchMetadata] {
        var result = try bundledAyurvedaMap()
        let profiles = try context.fetch(FetchDescriptor<AyurvedaProfile>())
        let profilesByFood = Dictionary(grouping: profiles, by: \.foodId)

        for (foodID, foodProfiles) in profilesByFood where foodID > 0 {
            let bundledAge = result[foodID]?.enforcedMinAgeMonths
            let userProfiles = foodProfiles.filter { $0.kind == "user" }

            if !userProfiles.isEmpty {
                if let preferred = userProfiles.first {
                    result[foodID] = AyurvedaCanonicalSearchMetadata(
                        profile: preferred,
                        enforcedMinAgeMonths: bundledAge
                    )
                }
                continue
            }

            if let preferred = foodProfiles.first {
                result[foodID] = AyurvedaCanonicalSearchMetadata(
                    profile: preferred,
                    enforcedMinAgeMonths: bundledAge
                )
            }
        }

        // Refresh linked rows from the live profiles as well, so an edited
        // dravya immediately updates exact/near/derived USDA matches.
        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, $0) }
        )
        let links = try context.fetch(FetchDescriptor<AyurvedaLink>())
        for link in links {
            if result[link.fdcId]?.sourceTier == nil,
               result[link.fdcId] != nil {
                continue
            }
            guard let profile = profilesByID[link.dravyaProfileId] else {
                continue
            }
            result[link.fdcId] = AyurvedaCanonicalSearchMetadata(
                profile: profile,
                enforcedMinAgeMonths: profile.foodId > 0
                    ? result[profile.foodId]?.enforcedMinAgeMonths
                    : nil,
                sourceTier: link.tier
            )
        }

        return result
    }

    private func ayurvedaSearchMetadata(
        foodID: Int,
        context: ModelContext
    ) -> AyurvedaCanonicalSearchMetadata? {
        let bundled = try? bundledAyurvedaMap()[foodID]
        let descriptor = FetchDescriptor<AyurvedaProfile>(
            predicate: #Predicate { $0.foodId == foodID }
        )
        guard let profiles = try? context.fetch(descriptor) else {
            return bundled
        }

        let userProfiles = profiles.filter { $0.kind == "user" }
        if let preferred = userProfiles.first {
            return AyurvedaCanonicalSearchMetadata(
                profile: preferred,
                enforcedMinAgeMonths: bundled?.enforcedMinAgeMonths
            )
        }

        if let preferred = profiles.first {
            return AyurvedaCanonicalSearchMetadata(
                profile: preferred,
                enforcedMinAgeMonths: bundled?.enforcedMinAgeMonths
            )
        }
        return bundled
    }

    private func rebuildNutrientIndexes(
        for nutrients: Set<NutrientType>
    ) {
        for nutrient in nutrients {
            let ranked = compactFoods.compactMap {
                item -> (id: Int, density: Double)? in
                guard let rawValue = item.nutrientValues[nutrient],
                      rawValue > 0,
                      item.referenceWeightG > 0 else {
                    return nil
                }
                return (
                    id: item.id,
                    density: (rawValue / item.referenceWeightG) * 100
                )
            }
            .sorted { $0.density > $1.density }

            if let maximum = ranked.first?.density {
                maxNutrientValues[nutrient] = maximum
                nutrientRankings[nutrient] = ranked.map(\.id)
            } else {
                maxNutrientValues.removeValue(forKey: nutrient)
                nutrientRankings.removeValue(forKey: nutrient)
            }
        }
    }

}

// MARK: - Codable Structures (Unchanged)

private struct SearchIndexPayload: Codable {
    struct CompactFoodCodable: Codable {
        let id: Int
        let name: String
        let searchTokens: [String]
        let minAgeMonths: Int
        let enforcedMinAgeMonths: Int
        let allergens: [String]
        let ph: Double
        let referenceWeightG: Double
        let isRecipe: Bool
        let isMenu: Bool
        let isFavorite: Bool
        let ayurvedaFacets: [String]
        let ayurvedaMetadata: AyurvedaCanonicalSearchMetadata?
        let nutrientValues: [String: Double]
    }

    let compactFoods: [CompactFoodCodable]
    let invertedIndex: [String: [Int]]
    let vocabulary: [String]
    let maxNutrientValues: [String: Double]
    let nutrientRankings: [String: [Int]]
    let ayurvedaFacetIndex: [String: [Int]]
}

// MARK: - Extensions for Encoding/Decoding Maps

private extension CompactFoodItem {
    func asCodable() -> SearchIndexPayload.CompactFoodCodable {
        SearchIndexPayload.CompactFoodCodable(
            id: id,
            name: name,
            searchTokens: Array(searchTokens),
            minAgeMonths: minAgeMonths,
            enforcedMinAgeMonths: enforcedMinAgeMonths,
            allergens: Array(allergens),
            ph: ph,
            referenceWeightG: referenceWeightG,
            isRecipe: isRecipe,
            isMenu: isMenu,
            isFavorite: isFavorite,
            ayurvedaFacets: Array(ayurvedaFacets),
            ayurvedaMetadata: ayurvedaMetadata,
            nutrientValues: Dictionary(uniqueKeysWithValues: nutrientValues.map { ($0.key.rawValue, $0.value) })
        )
    }

    init(_ codable: SearchIndexPayload.CompactFoodCodable) {
        let nutrientDict: [NutrientType: Double] = codable.nutrientValues.reduce(into: [:]) { dict, pair in
            if let t = NutrientType(rawValue: pair.key) { dict[t] = pair.value }
        }
        self.init(
            id: codable.id,
            name: codable.name,
            searchTokens: Set(codable.searchTokens),
            minAgeMonths: codable.minAgeMonths,
            enforcedMinAgeMonths: codable.enforcedMinAgeMonths,
            allergens: Set(codable.allergens),
            ph: codable.ph,
            referenceWeightG: codable.referenceWeightG,
            isRecipe: codable.isRecipe,
            isMenu: codable.isMenu,
            isFavorite: codable.isFavorite,
            ayurvedaFacets: Set(codable.ayurvedaFacets),
            ayurvedaMetadata: codable.ayurvedaMetadata,
            nutrientValues: nutrientDict
        )
    }
}

private func encodeMaxNutrientValues(_ dict: [NutrientType: Double]) -> [String: Double] {
    dict.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
}

private func decodeMaxNutrientValues(_ dict: [String: Double]) -> [NutrientType: Double] {
    dict.reduce(into: [:]) { if let t = NutrientType(rawValue: $1.key) { $0[t] = $1.value } }
}

private func encodeNutrientRankings(_ dict: [NutrientType: [Int]]) -> [String: [Int]] {
    dict.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
}

private func decodeNutrientRankings(_ dict: [String: [Int]]) -> [NutrientType: [Int]] {
    dict.reduce(into: [:]) { if let t = NutrientType(rawValue: $1.key) { $0[t] = $1.value } }
}
