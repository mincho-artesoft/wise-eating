import Foundation
import Combine
@preconcurrency import NaturalLanguage
import SwiftData

// Global embedding instance reused for semantic neighbors
private let smartFoodSearchEmbedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

fileprivate struct ProfileSearchConstraints: Sendable {
    let ageInMonths: Int
    let avoidedAllergens: Set<String> // Алергени, които профилът има (храната не трябва да ги съдържа)
}

@MainActor
final class SmartFoodSearch3: ObservableObject, @unchecked Sendable {

    // MARK: - Public Enums
    public enum SearchMode: String, CaseIterable, Identifiable, Sendable {
        case nutrients = "Nutrients"
        case recipes = "Recipes"
        case menus = "Menus"
        case mealPlans = "Meal Plans"
        
        public var id: String { rawValue }
    }
    
    // MARK: - Outputs (for UI)
    
    @Published var displayedResults: [FoodItem] = []
    @Published var isLoading: Bool = false
    @Published var searchContext: SearchContext = SearchContext()
    @Published private(set) var isAyurvedaSearchActive: Bool = false
    
    // MARK: - Internal Data (Lightweight Index)
    
    private var allFoods: [CompactFoodItem] = []
    private var loadedIndexRevision: UInt64 = 0
    
    /// token -> set of CompactFoodItem IDs
    private var invertedIndex: [String: Set<Int>] = [:]

    /// Ayurveda facet key -> direct, USDA-linked and user-created FoodItem IDs
    private var ayurvedaFacetIndex: [String: Set<Int>] = [:]
    
    /// id -> CompactFoodItem
    private var compactMap: [Int: CompactFoodItem] = [:]
    
    private var vocabulary: [String] = []
    private var maxNutrientValues: [NutrientType: Double] = [:]
    
    /// Optional: nutrient-based candidate lists from NutrientIndex
    private var nutrientRankings: [NutrientType: [Int]] = [:]
    
    // MARK: - Search State
    
    private var lastCanonicalQuery: String = ""
    private var lastActiveFilters: Set<NutrientType> = []
    private var lastQuickAgeMonths: Double? = nil
    private var lastForcePhDisplay: Bool = false
    private var lastIsFavoritesOnly: Bool = false
    private var lastIsRecipesOnly: Bool = false
    private var lastIsMenusOnly: Bool = false
    private var lastAyurvedaFilters: AyurvedaSearchFilters = .empty
    private var lastConstitutionTarget: AyurvedaDoshaDistribution?
    
    // --- NEW: Track last mode & excluded IDs ---
    private var lastSearchMode: SearchMode? = nil
    private var lastExcludedFoodIDs: Set<Int> = []      // ✅ ново
    
    private var fullResultIDs: [Int] = []       // sorted IDs
    private let pageSize: Int = 40
    
    private var searchTask: Task<Void, Never>?
    private let container: ModelContainer
    private var lastPhSortOrder: PhSortOrder? = nil
    // MARK: - Init
    
    init(container: ModelContainer) {
        self.container = container
        SearchKnowledgeBase.shared.loadSynonymsFromBundle()
    }
    
    public enum PhSortOrder: Sendable {
        case lowToHigh // Acidic -> Alkaline
        case highToLow // Alkaline -> Acidic
        case neutral   // ✅ НОВО
    }
    
    // MARK: - Public API
        func performSearch(
            query rawQuery: String,
            activeFilters: Set<NutrientType> = [],
            quickAgeMonths: Double? = nil,
            forcePhDisplay: Bool = false,
            isFavoritesOnly: Bool = false,
            isRecipesOnly: Bool = false,
            isMenusOnly: Bool = false,
            searchMode: SearchMode? = nil,
            profile: Profile? = nil,
            excludedFoodIDs: Set<Int> = [],
            ayurvedaFilters: AyurvedaSearchFilters = .empty,
            phSortOrder: PhSortOrder? = nil // ✅ НОВ ПАРАМЕТЪР
        ) {
            let store = SearchIndexStore.shared
            if !store.compactFoods.isEmpty,
               loadedIndexRevision != store.revision {
                applyLoadedIndex()
            }

            // A newly-created search engine may receive a query before its
            // lightweight index has been copied from SearchIndexStore. Defer
            // the latest request instead of searching an empty snapshot.
            guard !allFoods.isEmpty else {
                searchTask?.cancel()
                isLoading = true
                searchTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    let hasSearchData = await self.prepareForSearch()
                    guard !Task.isCancelled else { return }

                    guard hasSearchData else {
                        self.isLoading = false
                        self.clearResults()
                        return
                    }

                    self.performSearch(
                        query: rawQuery,
                        activeFilters: activeFilters,
                        quickAgeMonths: quickAgeMonths,
                        forcePhDisplay: forcePhDisplay,
                        isFavoritesOnly: isFavoritesOnly,
                        isRecipesOnly: isRecipesOnly,
                        isMenusOnly: isMenusOnly,
                        searchMode: searchMode,
                        profile: profile,
                        excludedFoodIDs: excludedFoodIDs,
                        ayurvedaFilters: ayurvedaFilters,
                        phSortOrder: phSortOrder
                    )
                }
                return
            }

            let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)
            
            print("\n=============================================================")
            print("🔍 [SmartSearch] STARTING SEARCH: '\(rawQuery)' | Mode: \(searchMode?.rawValue ?? "None") | pH Order: \(String(describing: phSortOrder))")
            print("=============================================================\n")
            
            var profileConstraints: ProfileSearchConstraints? = nil
            let constitutionTarget: AyurvedaDoshaDistribution?
            if let p = profile {
                profileConstraints = ProfileSearchConstraints(
                    ageInMonths: p.ageInMonths,
                    avoidedAllergens: Set(p.allergens.map { $0.rawValue })
                )
                constitutionTarget = AyurvedaConstitutionStore
                    .record(for: p.id)?
                    .target()
            } else {
                constitutionTarget = nil
            }
            
            let sameQuery =
                canonicalQuery == lastCanonicalQuery &&
                activeFilters == lastActiveFilters &&
                quickAgeMonths == lastQuickAgeMonths &&
                forcePhDisplay == lastForcePhDisplay &&
                isFavoritesOnly == lastIsFavoritesOnly &&
                isRecipesOnly == lastIsRecipesOnly &&
                isMenusOnly == lastIsMenusOnly &&
                searchMode == lastSearchMode &&
                excludedFoodIDs == lastExcludedFoodIDs &&
                ayurvedaFilters == lastAyurvedaFilters &&
                constitutionTarget == lastConstitutionTarget &&
                phSortOrder == lastPhSortOrder // ✅ Проверка и за pH
            
            // Проверка дали имаме данни, но не ги показваме
            let isDataReadyButHidden = !allFoods.isEmpty && displayedResults.isEmpty
            
            // Когато всичко е празно И няма изключени ID-та И няма searchMode → default results
            if canonicalQuery.isEmpty,
               activeFilters.isEmpty,
               quickAgeMonths == nil,
               forcePhDisplay == false,
               !isFavoritesOnly,
               !isRecipesOnly,
               !isMenusOnly,
               searchMode == nil,
               excludedFoodIDs.isEmpty,
               !ayurvedaFilters.isActive,
               constitutionTarget == nil,
               phSortOrder == nil { // ✅ Проверка и за pH
                
                print("ℹ️ [SmartSearch] Empty query detected. Attempting to show default results.")
                
                lastCanonicalQuery = canonicalQuery
                lastActiveFilters  = activeFilters
                lastQuickAgeMonths = quickAgeMonths
                lastForcePhDisplay = forcePhDisplay
                lastIsFavoritesOnly = isFavoritesOnly
                lastIsRecipesOnly = isRecipesOnly
                lastIsMenusOnly = isMenusOnly
                lastSearchMode = searchMode
                lastExcludedFoodIDs = excludedFoodIDs
                lastAyurvedaFilters = ayurvedaFilters
                lastConstitutionTarget = constitutionTarget
                lastPhSortOrder = phSortOrder // ✅ Обновяване на state
                
                searchTask?.cancel()
                isLoading = false
                showDefaultResultsIfPossible()
                return
            }
            
            // Ако заявката е същата, НО нямаме скрити данни за показване -> спираме.
            if sameQuery && !isDataReadyButHidden {
                print("ki [SmartSearch] Skipping search: Query is identical and data is already displayed.")
                return
            }
            
            searchTask?.cancel()
            lastCanonicalQuery = canonicalQuery
            lastActiveFilters  = activeFilters
            lastQuickAgeMonths = quickAgeMonths
            lastForcePhDisplay = forcePhDisplay
            lastIsFavoritesOnly = isFavoritesOnly
            lastIsRecipesOnly = isRecipesOnly
            lastIsMenusOnly = isMenusOnly
            lastSearchMode = searchMode
            lastExcludedFoodIDs = excludedFoodIDs
            lastAyurvedaFilters = ayurvedaFilters
            lastConstitutionTarget = constitutionTarget
            lastPhSortOrder = phSortOrder // ✅ Обновяване на state
            
            // Snapshot lightweight state
            let snapshotAllFoods = allFoods
            let snapshotMap = compactMap
            let snapshotIndex = invertedIndex
            let snapshotFacetIndex = ayurvedaFacetIndex
            let snapshotVocab = vocabulary
            let snapshotMaxValues = maxNutrientValues
            let snapshotRankings = nutrientRankings
            let snapshotExcludedIDs = excludedFoodIDs
            let temporalContext = AyurvedaSearchTemporalContext.current()
            
            isLoading = true
            searchTask = Task.detached(
                priority: .userInitiated
            ) { [weak self,
                 snapshotAllFoods,
                 snapshotMap,
                 snapshotIndex,
                 snapshotFacetIndex,
                 snapshotVocab,
                 snapshotMaxValues,
                 snapshotRankings,
                 snapshotExcludedIDs] in
                
                // 🛑 Ако вече сме деинициализирани – спираме
                guard let self else { return }
                
                if Task.isCancelled { return }
                
                // Expand dynamic OR variants based on the canonical query.
                let queryVariants = SmartFoodSearch3.expandOrVariants(canonicalQuery)
                print("🚀 [SmartSearch] Task started for canonical query: '\(canonicalQuery)' | variants: \(queryVariants)")
                
                var aggregatedIDs = Set<Int>()
                var orderedResultIDs: [Int] = []
                var primaryIntent: SearchIntent?
                var primaryForceShowPH = false
                var primaryFoodsWithoutPhExcluded = 0
                
                for (index, variantQuery) in queryVariants.enumerated() {
                    if Task.isCancelled { return }
                    
                    let (
                        resultIDs,
                        intent,
                        _,
                        forceShowPH,
                        foodsWithoutPhExcluded
                    ) = await self.runSearchLogic(
                        query: variantQuery,
                        activeFilters: activeFilters,
                        compactMap: snapshotMap,
                        allFoods: snapshotAllFoods,
                        maxValues: snapshotMaxValues,
                        invertedIndex: snapshotIndex,
                        ayurvedaFacetIndex: snapshotFacetIndex,
                        vocabulary: snapshotVocab,
                        nutrientRankings: snapshotRankings,
                        quickAgeMonths: quickAgeMonths,
                        forcePhDisplay: forcePhDisplay,
                        isFavoritesOnly: isFavoritesOnly,
                        isRecipesOnly: isRecipesOnly,
                        isMenusOnly: isMenusOnly,
                        searchMode: searchMode,
                        profileConstraints: profileConstraints,
                        excludedFoodIDs: snapshotExcludedIDs,
                        ayurvedaFilters: ayurvedaFilters,
                        temporalContext: temporalContext,
                        constitutionTarget: constitutionTarget,
                        phSortOrder: phSortOrder,
                        container: self.container
                    )
                    
                    if index == 0 {
                        primaryIntent = intent
                        primaryForceShowPH = forceShowPH
                        primaryFoodsWithoutPhExcluded = foodsWithoutPhExcluded
                    }
                    
                    for id in resultIDs {
                        if aggregatedIDs.insert(id).inserted {
                            orderedResultIDs.append(id)
                        }
                    }
                }
                
                if Task.isCancelled {
                    print("🛑 [SmartSearch] Task cancelled before UI update.")
                    return
                }
                
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    
                    print("✅ [SmartSearch] Updating UI on MainActor. Aggregated IDs: \(orderedResultIDs.count)")
                    
                    self.isLoading = false
                    self.fullResultIDs = orderedResultIDs
                    
                    if let intent = primaryIntent {
                        self.isAyurvedaSearchActive = ayurvedaFilters.isActive
                            || !intent.ayurvedaFacetConstraints.isEmpty
                        self.updateContext(
                            intent: intent,
                            activeFilters: activeFilters,
                            ayurvedaFilters: ayurvedaFilters,
                            forceShowPH: primaryForceShowPH,
                            foodsWithoutPhExcluded: primaryFoodsWithoutPhExcluded
                        )
                    }
                    
                    if self.fullResultIDs.isEmpty {
                        self.displayedResults = []
                        print("⚠️ [SmartSearch] Result list is empty.")
                    } else {
                        self.loadDisplayBatch(startIndex: 0)
                    }
                }
            }

        }
    
    private func showDefaultResultsIfPossible() {
        print("🔄 [SmartSearch] showDefaultResultsIfPossible called. AllFoods count: \(allFoods.count)")
        
        guard !allFoods.isEmpty else {
            print("⚠️ [SmartSearch] allFoods is empty. Clearing results.")
            clearResults()
            return
        }
        let sorted = allFoods.sorted { $0.lowercasedName < $1.lowercasedName }
        fullResultIDs = sorted.map { $0.id }
        searchContext = SearchContext()
        isAyurvedaSearchActive = false
        displayedResults = [] // Изчистваме първо, за да форсираме refresh
        
        print("🔄 [SmartSearch] Loading default batch (0)...")
        loadDisplayBatch(startIndex: 0)
    }
    
    func loadMoreResults() {
        let currentCount = displayedResults.count
        guard currentCount < fullResultIDs.count else { return }
        loadDisplayBatch(startIndex: currentCount)
    }
    
    // MARK: - Display Helpers
        
    func normalizedAndScaledValue(for food: FoodItem, nutrient: NutrientType) -> (value: Double, unit: String)? {
        let (totalValue, calculatedUnit) = food.calculatedNutrition(for: nutrient)
        let referenceWeight = food.referenceWeightG
        guard referenceWeight > 0, totalValue.isFinite else { return nil }

        // FoodItem's legacy accessors use 0.0 for both a stored zero and an
        // absent relationship. A stored Nutrient still carries its unit, so
        // preserve that real zero while treating the unitless sentinel as
        // missing. Non-zero values can safely use the canonical unit fallback.
        guard calculatedUnit != nil || abs(totalValue) > 0.000001 else {
            return nil
        }
        
        let valuePer100g = (totalValue / referenceWeight) * 100.0
        
        // 1. Determine Unit: Use FoodItem's unit OR fallback to KnowledgeBase defaults
        let unit = calculatedUnit ?? SearchKnowledgeBase.shared.defaultUnit(for: nutrient)
        
        // 2. Handle Zero Values explicitely
        if valuePer100g <= 0.000001 {
            return (0.0, unit)
        }
        
        // 3. Scaling Logic (for non-zero values)
        var v = valuePer100g
        var u = unit.lowercased()
        
        // Scale down (mg -> g) if huge
        while v >= 1000 {
            switch u {
            case "ng": v /= 1000; u = "µg"
            case "µg", "mcg": v /= 1000; u = "mg"
            case "mg": v /= 1000; u = "g"
            case "g": v /= 1000; u = "kg"
            default: break
            }
            if u == unit.lowercased() { break }
        }
        
        // Scale up (g -> mg) if tiny
        while v < 1 && v > 0 {
            switch u {
            case "kg": v *= 1000; u = "g"
            case "g": v *= 1000; u = "mg"
            case "mg": v *= 1000; u = "µg"
            case "µg": v *= 1000; u = "ng"
            default: break
            }
            if u == unit.lowercased() { break }
        }
        
        let displayUnit = (u == unit.lowercased()) ? unit : u
        return (v, displayUnit)
    }
    
    // MARK: - Display Batch
    
    // MARK: - Display Batch
        
    private func loadDisplayBatch(startIndex: Int) {
        let endIndex = min(startIndex + pageSize, fullResultIDs.count)
        
        print("📦 [SmartSearch] loadDisplayBatch: Requesting indices \(startIndex) to \(endIndex) (Total IDs: \(fullResultIDs.count))")
        
        let idsToFetch = Array(fullResultIDs[startIndex..<endIndex])
        guard !idsToFetch.isEmpty else {
            print("⚠️ [SmartSearch] loadDisplayBatch: No IDs to fetch.")
            return
        }
        
        let context = container.mainContext
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { idsToFetch.contains($0.id) }
        )
        
        do {
            let fetched = try context.fetch(descriptor)
            let idMap = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let sortedItems = idsToFetch.compactMap { idMap[$0] }
            
            print("📦 [SmartSearch] Fetched \(sortedItems.count) items from DB.")
            
            if startIndex == 0 {
                // Тук е критичният момент - присвояваме изцяло нов масив
                displayedResults = sortedItems
                print("✅ [SmartSearch] displayedResults REPLACED with \(sortedItems.count) items.")
            } else {
                displayedResults.append(contentsOf: sortedItems)
                print("➕ [SmartSearch] displayedResults APPENDED. New count: \(displayedResults.count)")
            }
        } catch {
            print("❌ [SmartSearch] Error fetching display batch: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func clearResults() {
        fullResultIDs = []
        displayedResults = []
        searchContext = SearchContext()
        isAyurvedaSearchActive = false
    }

    func ayurvedaMetadata(
        for foodID: Int
    ) -> AyurvedaCanonicalSearchMetadata? {
        compactMap[foodID]?.ayurvedaMetadata
    }
    
    private func updateContext(intent: SearchIntent,
                               activeFilters: Set<NutrientType>,
                               ayurvedaFilters: AyurvedaSearchFilters,
                               forceShowPH: Bool,
                               foodsWithoutPhExcluded: Int) {
        var display = intent.displayNutrients
        for goal in intent.nutrientGoals where !display.contains(goal.nutrient) {
            display.append(goal.nutrient)
        }
        for f in activeFilters.sorted(by: { $0.rawValue < $1.rawValue })
        where !display.contains(f) {
            display.append(f)
        }
        var seen = Set<NutrientType>()
        let uniqueDisplay = display.filter { seen.insert($0).inserted }
        let activeConstraint = intent.nutrientGoals.isEmpty
            ? nil
            : intent.nutrientGoals
                .map(\.searchContextDescription)
                .joined(separator: ", ")
        var ageStr: String? = nil
        if let age = intent.targetConsumerAge {
            ageStr = age >= 12 ? "\(Int(age / 12))y+" : "\(Int(age))m+"
        }
        var ayurvedaFields = Set<AyurvedaSearchDisplayField>()
        for constraint in intent.ayurvedaFacetConstraints {
            for key in constraint.acceptedKeys {
                guard let facet = AyurvedaFacet(key: key) else { continue }
                switch facet.kind {
                case .rasa:
                    ayurvedaFields.insert(.rasa)
                case .virya:
                    ayurvedaFields.insert(.virya)
                case .vipaka:
                    ayurvedaFields.insert(.vipaka)
                case .guna:
                    ayurvedaFields.insert(.guna)
                case .agni:
                    ayurvedaFields.insert(.agni)
                case .digestibility:
                    ayurvedaFields.insert(.digestibility)
                case .season:
                    ayurvedaFields.insert(.season)
                case .concept where facet.value == "digestion":
                    ayurvedaFields.insert(.digestion)
                default:
                    break
                }
            }
        }
        if !ayurvedaFilters.rasa.isEmpty {
            ayurvedaFields.insert(.rasa)
        }
        if ayurvedaFilters.virya != nil {
            ayurvedaFields.insert(.virya)
        }
        if !ayurvedaFilters.gunas.isEmpty {
            ayurvedaFields.insert(.guna)
        }
        if ayurvedaFilters.easyOnDigestion {
            ayurvedaFields.insert(.digestion)
        }
        let orderedAyurvedaFields = AyurvedaSearchDisplayField.allCases
            .filter(ayurvedaFields.contains)

        searchContext = SearchContext(
            displayNutrients: uniqueDisplay,
            displayAyurvedaFields: orderedAyurvedaFields,
            activeConstraint: activeConstraint,
            activeAgeLimit: ageStr,
            isPhActive: forceShowPH || intent.phConstraint != nil,
            foodsWithoutPhExcluded: foodsWithoutPhExcluded
        )
    }
    
        // MARK: - Core Logic
            
        nonisolated private func runSearchLogic(
            query: String,
            activeFilters: Set<NutrientType>,
            compactMap: [Int: CompactFoodItem],
            allFoods: [CompactFoodItem],
            maxValues: [NutrientType: Double],
            invertedIndex: [String: Set<Int>],
            ayurvedaFacetIndex: [String: Set<Int>],
            vocabulary: [String],
            nutrientRankings: [NutrientType: [Int]],
            quickAgeMonths: Double?,
            forcePhDisplay: Bool,
            isFavoritesOnly: Bool,
            isRecipesOnly: Bool,
            isMenusOnly: Bool,
            searchMode: SearchMode?,
            profileConstraints: ProfileSearchConstraints?,
            excludedFoodIDs: Set<Int>,
            ayurvedaFilters: AyurvedaSearchFilters,
            temporalContext: AyurvedaSearchTemporalContext,
            constitutionTarget: AyurvedaDoshaDistribution?,
            phSortOrder: PhSortOrder?, // ✅ НОВ ПАРАМЕТЪР
            container: ModelContainer
        ) async -> (
            resultIDs: [Int],
            intent: SearchIntent,
            effectiveTokens: [String],
            forceShowPH: Bool,
            foodsWithoutPhExcluded: Int
        ) {
            
            let originalSimpleRawQuery = query
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedFacets = CanonicalFacetParser.parse(
                query,
                synonyms: SearchKnowledgeBase.shared.synonyms
            )
            let facetParse: AyurvedaFacetParseResult
            if parsedFacets.constraints.isEmpty {
                facetParse = parsedFacets
            } else {
                let exactNameMatch = allFoods.contains {
                    $0.lowercasedName == originalSimpleRawQuery
                }
                facetParse = exactNameMatch
                    ? AyurvedaFacetParseResult.passthrough(query)
                    : parsedFacets
            }
            let searchQuery = facetParse.remainingQuery
            let simpleRawQuery = searchQuery
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let hasNonLatinLetters: Bool = simpleRawQuery.unicodeScalars.contains { scalar in
                if scalar.isASCII { return false }
                if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
                if CharacterSet.punctuationCharacters.contains(scalar) { return false }
                return true
            }
            
            let queryBoundary = ConstraintQueryBoundary(searchQuery)
            let rawPhCount = queryBoundary.count(of: "ph")
            
            let parsed = await Tokenizer.parse(searchQuery)
            let hasDigits = searchQuery.rangeOfCharacter(from: .decimalDigits) != nil
            var textTokens = parsed.textTokens

            if !facetParse.constraints.isEmpty, !parsed.nutrientGoals.isEmpty {
                let nutrientModifiers: Set<String> = [
                    "high",
                    "higher",
                    "low",
                    "lower",
                    "rich",
                    "poor",
                ]
                textTokens.subtract(nutrientModifiers)
            }
            
            // --- 🟢 BUG FIX START: FORCE RAW TOKENS ---
            // If the user types "rice", and Tokenizer converts it to "grain",
            // but the DB only has "rice", we must ensure "rice" is searched.
            let rawQueryTokens = simpleRawQuery
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            
            for rawToken in rawQueryTokens {
                // Check if this raw token actually exists in our DB index.
                if invertedIndex[rawToken] != nil {
                    // If it exists in DB, add it to search tokens even if Tokenizer removed/changed it.
                    // But skip common stop words to avoid noise (e.g. "with").
                    let isStopWord = SearchKnowledgeBase.shared.stopWords.contains(rawToken)
                    let isFacetNutrientModifier =
                        !facetParse.constraints.isEmpty
                        && !parsed.nutrientGoals.isEmpty
                        && ["high", "higher", "low", "lower", "rich", "poor"]
                            .contains(rawToken)
                    let isFacetNutrientToken =
                        !facetParse.constraints.isEmpty
                        && SearchKnowledgeBase.shared.nutrientMap[rawToken]
                            .map { nutrient in
                                parsed.nutrientGoals.contains {
                                    $0.nutrient == nutrient
                                }
                            } == true
                    if !isStopWord
                        && !isFacetNutrientModifier
                        && !isFacetNutrientToken
                        && !textTokens.contains(rawToken) {
                        textTokens.insert(rawToken)
                    }
                }
            }
            // --- 🟢 BUG FIX END ---
            
            let simplePHToggle = (rawPhCount >= 1 && !hasDigits)
            
            if simplePHToggle {
                textTokens = textTokens.filter { $0.caseInsensitiveCompare("ph") != .orderedSame }
            }

            // Remove standalone "or" tokens – logical OR is handled at a higher level.
            textTokens = textTokens.filter { $0.caseInsensitiveCompare("or") != .orderedSame }
            
            let combinedAge = quickAgeMonths ?? parsed.targetConsumerAge
            
            let forceShowPH = simplePHToggle || (rawPhCount >= 2 && parsed.phConstraint == nil) || forcePhDisplay
            
            // --- ПРИОРИТЕТИ ---
            var mergedGoals: [NutrientGoal] = []
            
            // 1. Филтри от UI
            for filter in activeFilters.sorted(by: { $0.rawValue < $1.rawValue }) {
                mergedGoals.append(NutrientGoal(nutrient: filter, constraint: .high))
            }
            
            // 2. Цели от текст
            for goal in parsed.nutrientGoals {
                if !mergedGoals.contains(where: { $0.nutrient == goal.nutrient }) {
                    mergedGoals.append(goal)
                }
            }
            
            // --- Constraint Engine ---
            let mappedConstraints: ConstraintMapperResult
            let lowerQuery = searchQuery.lowercased()
            let shouldUseConstraintEngine: Bool = {
                if lowerQuery.rangeOfCharacter(from: .decimalDigits) != nil { return true }
                if queryBoundary.containsAnyToken(["ph", "acid", "alkaline"]) {
                    return true
                }
                if queryBoundary.containsFreeConstraint()
                    || queryBoundary.containsAnyToken(["without", "no"]) {
                    return true
                }
                if queryBoundary.containsPhrase(["less", "than"])
                    || queryBoundary.containsPhrase(["more", "than"])
                    || queryBoundary.containsPhrase(["at", "least"])
                    || queryBoundary.containsPhrase(["at", "most"])
                    || queryBoundary.containsAnyToken(["between", "from"]) {
                    return true
                }
                if queryBoundary.containsAnyToken(["low", "high", "rich", "poor"]) {
                    return true
                }
                return false
            }()
            
            if shouldUseConstraintEngine {
                print("🧮 [Constraints] Using constraint engine for query: \(searchQuery)")
                mappedConstraints = await MainActor.run {
                    let rawConstraints = ConstraintExtractor.extract(from: searchQuery)
                    return ConstraintMapper.map(rawConstraints)
                }
            } else {
                mappedConstraints = ConstraintMapperResult()
            }
            
            var numericGoals = mappedConstraints.nutrientGoals
            let fallbackGoals = SmartFoodSearch3.parseNumericNutrientConstraintsFromQuery(searchQuery)
            if !fallbackGoals.isEmpty {
                for goal in fallbackGoals {
                    if let index = numericGoals.firstIndex(where: { $0.nutrient == goal.nutrient }) {
                        numericGoals[index] = goal
                    } else {
                        numericGoals.append(goal)
                    }
                }
            }
            
            // Merge numeric goals into our prioritized list
            mergedGoals = SmartFoodSearch3.mergeNumericGoals(numericGoals, into: mergedGoals)
            let displayNutrients = SmartFoodSearch3.orderedDisplayNutrients(
                in: searchQuery,
                goalGroups: [
                    parsed.nutrientGoals,
                    mappedConstraints.nutrientGoals,
                    fallbackGoals,
                ]
            )
            
            var combinedAllergenExclusions = parsed.allergenExclusions.union(mappedConstraints.excludeAllergens)
            
            // --- ✅ pH Logic Update with Explicit Sort Order ---
            let phConstraintFromConstraints = mappedConstraints.phConstraint
            
            // 1. Първо проверяваме изричния аргумент от UI
            let explicitPhConstraint: ConstraintValue?
            switch phSortOrder {
            case .lowToHigh:
                explicitPhConstraint = .lowest
            case .highToLow:
                explicitPhConstraint = .highest
            case .neutral:
                explicitPhConstraint = .range(
                    PhSearchSemantics.neutralLowerBound,
                    PhSearchSemantics.neutralUpperBound
                )
            case nil:
                explicitPhConstraint = nil
            }
            // 2. Приоритет: UI Бутон > Constraint Engine > Tokenizer
            let phConstraintForIntent = explicitPhConstraint
                                        ?? phConstraintFromConstraints
                                        ?? (simplePHToggle ? nil : parsed.phConstraint)
            // --------------------------------------------------
            
            func makeIntent() -> SearchIntent {
                SearchIntent(
                    textTokens: textTokens,
                    negativeTokens: parsed.negativeTokens,
                    nutrientGoals: mergedGoals,
                    displayNutrients: displayNutrients,
                    targetConsumerAge: combinedAge,
                    allergenExclusions: combinedAllergenExclusions,
                    excludeAllAllergens: parsed.excludeAllAllergens,
                    phConstraint: phConstraintForIntent,
                    ayurvedaFacetConstraints: facetParse.constraints
                )
            }
            
            let enableFuzzyTypos = textTokens.count >= 3
            let vocabSet = Set(vocabulary)

            // Marker tokens that switch the query into "exclude next ingredient" mode,
            // based on the RAW query text (so we don't depend on Tokenizer keeping them).
            // Examples: "no tomato", "without sugar", "exclude chicken", "minus cheese".
            let phraseNegativeMarkers: Set<String> = [
                "no", "without", "excluding", "exclude", "except", "minus"
            ]

            // Expanded list based on USDA database semantic analysis.
            // Currently not all of these are used directly in SmartFoodSearch3, but
            // keeping them centralized here allows future semantic refinements.
            let negativeMarkers: Set<String> = [
                // Standard Query Negations
                "no", "without", "excluding", "exclude", "except", "minus", "not", "non",

                // "Free" compounds (e.g. fat free, sugar free, gluten free, caffeine free)
                "free",

                // "Less" compounds (e.g. boneless, skinless, meatless, seedless)
                "less",

                // "Un" prefix indicators (e.g. unsweetened, unsalted, unheated, unprepared, unpeeled)
                "un",

                // "Non" prefix indicators (explicit forms)
                "nonfat", "nondairy", "nonalcoholic",

                // Specific state exclusions
                "removed", // e.g. skin removed
                "plain",   // often implies "no flavoring/sauce"
                "raw",     // implies "not cooked"
                "fresh"    // often implies "not frozen/canned"
            ]

            // Robust negative-ingredient detection:
            //   • Parse the RAW query string so "exclude" or "without" cannot be dropped
            //     by Tokenizer.
            //   • For each marker, grab the next word as the candidate ingredient.
            //   • If the candidate matches a known ingredient or a token in the vocabulary,
            //     treat it as a negative ingredient.
            //   • Also map ingredients to allergens when possible (e.g. "no milk" -> Dairy).
            var negativeIngredients = Set<String>()
            let ingredientKeys = vocabSet

            let rawWordsForNegatives: [String] = simpleRawQuery
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            for i in 0..<rawWordsForNegatives.count {
                let word = rawWordsForNegatives[i].lowercased()
                guard phraseNegativeMarkers.contains(word) else { continue }
                guard i + 1 < rawWordsForNegatives.count else { continue }

                // Look ahead for the ingredient token after the marker: "exclude" -> "chicken"
                var candidate = rawWordsForNegatives[i + 1].lowercased()

                // Strip punctuation around the candidate (e.g. "chicken," -> "chicken")
                candidate = candidate.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard !candidate.isEmpty else { continue }

                // Simple singularization: "tomatoes" -> "tomato" when we know that form exists.
                if candidate.hasSuffix("s"), candidate.count > 3 {
                    let singular = String(candidate.dropLast())
                    if ingredientKeys.contains(singular) || vocabSet.contains(singular) {
                        candidate = singular
                    }
                }

                // Accept as a negative ingredient if:
                //   • it is a known ingredient, OR
                //   • it exists in the search vocabulary (e.g. "chicken").
                if ingredientKeys.contains(candidate) || vocabSet.contains(candidate) {
                    negativeIngredients.insert(candidate)
                    // Optional: map "no milk" / "without milk" → allergen exclusion.
                    if let mappedAllergen = SearchKnowledgeBase.shared.allergenForIngredient(candidate) {
                        combinedAllergenExclusions.insert(mappedAllergen)
                        print("🚫 [SmartSearch] 'no/without/exclude \(candidate)' mapped to Allergen: \(mappedAllergen)")
                    }
                }
            }

            // Remove negative markers and their ingredients from the *positive* text tokens
            // so that "exclude chicken" does not also act as a positive "chicken" search.
            textTokens = textTokens.filter { token in
                let lower = token.lowercased()
                if phraseNegativeMarkers.contains(lower) { return false }
                if negativeIngredients.contains(lower) { return false }
                return true
            }

            let tokenIsCommandPrefix: [String: Bool] = await MainActor.run {
                var map: [String: Bool] = [:]
                for t in textTokens {
                    let lower = t.lowercased()
                    
                    // Original system keyword detection
                    let rawIsPrefix = SearchKnowledgeBase.shared.isSystemKeywordPrefix(t)
                    
                    // "ph" and "no" remain special 2-char commands
                    let isCommand: Bool = (t.count <= 2) ? (lower == "ph" || lower == "no") : rawIsPrefix
                    
                    map[t] = isCommand
                }
                return map
            }
            
            var candidateIDs: Set<Int>? = nil
            var effectiveTextTokens: [String] = []
            let trimmedNumericQuery = searchQuery
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isPureNumericQuery = !trimmedNumericQuery.isEmpty && trimmedNumericQuery.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
            
            if isPureNumericQuery {
                var numericMatches = Set<Int>()
                for item in allFoods where item.lowercasedName.contains(trimmedNumericQuery) {
                    numericMatches.insert(item.id)
                }
                if !numericMatches.isEmpty {
                    candidateIDs = numericMatches
                    effectiveTextTokens = [trimmedNumericQuery]
                }
            }
            
            if !textTokens.isEmpty && !hasNonLatinLetters {
                let sortedTokens = textTokens.sorted { a, b in
                    let aIsPrefix = tokenIsCommandPrefix[a] ?? false
                    let bIsPrefix = tokenIsCommandPrefix[b] ?? false
                    if aIsPrefix != bIsPrefix { return !aIsPrefix }
                    return a < b
                }
                
                for term in sortedTokens {
                    let lower = term.lowercased()
                    // Skip explicit negative markers and the ingredients they negate.
                    if negativeIngredients.contains(lower) { continue }
                    if phraseNegativeMarkers.contains(lower) { continue }

                    let isCommandPrefix = tokenIsCommandPrefix[term] ?? false
                    let isShortSoftToken = (term.count <= 2 && candidateIDs != nil && !isCommandPrefix)
                    var termMatches = Set<Int>()
                    if let ids = invertedIndex[term] { termMatches.formUnion(ids) }
                    
                    let isNumericOnly = term.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
                    if isNumericOnly {
                        if let ids = invertedIndex[term] { termMatches.formUnion(ids) }
                        if candidateIDs == nil { candidateIDs = termMatches }
                        else { candidateIDs?.formIntersection(termMatches) }
                        effectiveTextTokens.append(term)
                        continue
                    }
                    
                    if termMatches.isEmpty {
                        if term.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil { continue }
                        let commonUnits: Set<String> = ["kg", "g", "mg", "ug", "mcg", "lb", "lbs", "oz", "ml", "l"]
                        if commonUnits.contains(term.lowercased()) { continue }
                        let danglingComparators: Set<String> = ["less", "more", "greater", "fewer", "lower", "higher", "than", "equal", "under", "over", "above", "below", "exceeds", "at", "least", "most", "min", "max", "minimum", "maximum", "plus"]
                        if danglingComparators.contains(term.lowercased()) { continue }
                    }
                    
                    if !isCommandPrefix {
                        let prefixes = await findPrefixMatches(for: term, vocab: vocabulary)
                        for prefix in prefixes { if let ids = invertedIndex[prefix] { termMatches.formUnion(ids) } }
                        if enableFuzzyTypos && termMatches.isEmpty {
                            let semanticNeighbors = findSemanticNeighbors(for: term, vocab: vocabSet)
                            for neighbor in semanticNeighbors { if let ids = invertedIndex[neighbor] { termMatches.formUnion(ids) } }
                            if termMatches.isEmpty && term.count > 3 {
                                let typos = await findClosestWords(to: term, vocab: vocabulary)
                                for typo in typos { if let ids = invertedIndex[typo] { termMatches.formUnion(ids) } }
                            }
                        }
                    }
                    
                    if termMatches.isEmpty && !isCommandPrefix && term.count >= 3 {
                        let restored = term.replacingOccurrences(of: "_", with: " ")
                        if let (_, nutrient) = SearchKnowledgeBase.shared.nutrientMap.first(where: { (key, _) in key.hasPrefix(restored) }) {
                            mergedGoals.append(NutrientGoal(nutrient: nutrient, constraint: .high))
                            continue
                        }
                    }
                    
                    if isShortSoftToken {
                        if !termMatches.isEmpty { effectiveTextTokens.append(term) }
                        continue
                    }
                    
                    if term.count < 3, candidateIDs != nil, termMatches.isEmpty { continue }
                    let willResultInEmptySet = (candidateIDs?.isDisjoint(with: termMatches)) ?? termMatches.isEmpty
                    if willResultInEmptySet && isCommandPrefix { continue }
                    
                    if candidateIDs == nil { candidateIDs = termMatches }
                    else { candidateIDs?.formIntersection(termMatches) }
                    effectiveTextTokens.append(term)
                    if let current = candidateIDs, current.isEmpty { break }
                }
            }
            
            if Task.isCancelled {
                return ([], makeIntent(), [], forceShowPH, 0)
            }
            
            let intent = makeIntent()
            var finalCandidateIDs = candidateIDs
            
            // Ако няма текстови кандидати, зареждаме кандидатите за първата (най-приоритетна) цел
            if finalCandidateIDs == nil, let primaryGoal = intent.nutrientGoals.first, let rankedIDs = nutrientRankings[primaryGoal.nutrient] {
                finalCandidateIDs = Set(Array(rankedIDs.prefix(800)))
            }
            
            // Ако все още няма кандидати и имаме pH constraint, вземаме всички (филтърът ще ги намали)
            if finalCandidateIDs == nil && intent.phConstraint != nil {
                // Може да се оптимизира, но за безопасност минаваме през всички
            }
            
            let sequence: [CompactFoodItem] = finalCandidateIDs?.compactMap { compactMap[$0] } ?? allFoods
            var itemsToRank: [CompactFoodItem] = []
            var foodsWithoutPhExcluded = 0
            
            for (index, item) in sequence.enumerated() {
                if hasNonLatinLetters && (simpleRawQuery.isEmpty || !item.lowercasedName.contains(simpleRawQuery)) { continue }
                if index % 500 == 0 && Task.isCancelled {
                    return (
                        [],
                        intent,
                        [],
                        forceShowPH,
                        foodsWithoutPhExcluded
                    )
                }
                if excludedFoodIDs.contains(item.id) { continue }

                // Profiled foods must satisfy true facets. Unprofiled foods are
                // deliberately retained so the UI can explain the coverage gap.
                // Dosha constraints are handled only by scoring below.
                if let ayurveda = item.ayurvedaMetadata {
                    if !AyurvedaSearchRanker.matches(
                        ayurveda,
                        filters: ayurvedaFilters
                    ) {
                        continue
                    }
                    if !AyurvedaSearchRanker.matches(
                        ayurveda,
                        constraints: intent.ayurvedaFacetConstraints
                    ) {
                        continue
                    }
                }
                
                if let mode = searchMode {
                    switch mode {
                    case .recipes: if item.isRecipe || item.isMenu { continue }
                    case .menus: if item.isMenu { continue }
                    case .nutrients, .mealPlans:
                        if let cons = profileConstraints {
                            if Double(item.enforcedMinAgeMonths) > Double(cons.ageInMonths) { continue }
                            if !cons.avoidedAllergens.isEmpty {
                                var hasAllergen = false
                                for a in cons.avoidedAllergens { if item.contains(allergen: a) { hasAllergen = true; break } }
                                if hasAllergen { continue }
                            }
                        }
                    }
                }
                
                if isFavoritesOnly && !item.isFavorite { continue }
                if isRecipesOnly && !item.isRecipe { continue }
                if isMenusOnly && !item.isMenu { continue }
                if !item.searchTokens.isDisjoint(with: intent.negativeTokens) { continue }

                // Ingredient-level negative filter (e.g. "no tomato", "without tomato").
                // This now checks BOTH the visible name and the underlying searchTokens
                // to ensure strict exclusion (e.g. "exclude chicken" really removes all
                // items whose tokens contain "chicken"), while still allowing safe
                // contexts like "chicken-free", "excluding chicken", etc.
                if !negativeIngredients.isEmpty {
                    let lowerName = item.lowercasedName
                    var rejectDueToNegativeIngredient = false

                    for ing in negativeIngredients {
                        let token = ing.lowercased()

                        // 1. Check the underlying search tokens.
                        let hasTokenInSearchSet = item.searchTokens.contains(token)

                        // 2. Rough "mentions ingredient" check in the visible name.
                        let mentionsInName =
                            lowerName.contains(" \(token) ") ||
                            lowerName.hasPrefix("\(token) ") ||
                            lowerName.hasSuffix(" \(token)") ||
                            lowerName == token ||
                            lowerName.contains("\(token),") ||
                            lowerName.contains(", \(token)")

                        let mentionsIngredient = hasTokenInSearchSet || mentionsInName
                        guard mentionsIngredient else { continue }

                        // If the ingredient is only mentioned in exclusion phrases, keep it.
                        // Examples:
                        //   • "salad excluding tomato"
                        //   • "salad without tomato"
                        //   • "tomato-free dressing"
                        //   • "free of tomato"
                        let exclusionPhrases = [
                            "excluding \(token)",
                            "without \(token)",
                            "no \(token)",
                            "except \(token)",
                            "\(token) free",
                            "\(token)-free",
                            "free of \(token)"
                        ]
                        var isOnlyExcluded = false
                        for phrase in exclusionPhrases {
                            if lowerName.contains(phrase) {
                                isOnlyExcluded = true
                                break
                            }
                        }

                        if !isOnlyExcluded {
                            rejectDueToNegativeIngredient = true
                            break
                        }
                    }

                    if rejectDueToNegativeIngredient { continue }
                }

                if let age = intent.targetConsumerAge,
                   Double(item.enforcedMinAgeMonths) > age { continue }
                if intent.excludeAllAllergens && !item.allergens.isEmpty { continue }
                
                if !intent.allergenExclusions.isEmpty {
                    var hasAllergen = false
                    for ex in intent.allergenExclusions {
                        for keyword in SearchKnowledgeBase.shared.allergenKeywords(for: ex) where item.contains(allergen: keyword) { hasAllergen = true; break }
                        if hasAllergen { break }
                    }
                    if hasAllergen { continue }
                }
                
                if let phLimit = intent.phConstraint {
                    if !PhSearchSemantics.hasData(item.ph) {
                        foodsWithoutPhExcluded += 1
                        continue
                    }
                    if !PhSearchSemantics.matches(item.ph, constraint: phLimit) {
                        continue
                    }
                }
                
                var passesNutrients = true
                for goal in intent.nutrientGoals {
                    // raw per-100 g value from the index
                    let rawVal: Double = (item.referenceWeightG > 0)
                        ? (item.value(for: goal.nutrient) / item.referenceWeightG) * 100.0
                        : 0.0

                    // 🔢 Round everything to a single decimal place so that
                    // 45.49 -> 45.5 and comparisons are always done at 0.1 precision.
                    let val = SmartFoodSearch3.roundToSingleDecimal(rawVal)

                    // 🔎 Трактуваме 0 като "липсва данни" при ЧИСЛОВИ ограничения,
                    // за да не минават храни с 0 витамин C при "vitamin c < 2mcg".
                    let isNumericConstraint: Bool
                    switch goal.constraint {
                    case .min, .max, .strictMin, .strictMax, .range, .notEqual:
                        isNumericConstraint = true
                    case .high, .low, .lowest, .highest:
                        isNumericConstraint = false
                    }

                    if isNumericConstraint && val == 0 {
                        passesNutrients = false
                        print("🧪 [SmartSearch] Excluding '\(item.lowercasedName)' for \(goal.nutrient) – numeric constraint \(goal.constraint) but rounded value is 0.0")
                        break
                    }

                    // DEBUG: see exactly what we're comparing
                    print("⚖️ [SmartSearch] Checking \(goal.nutrient) for '\(item.lowercasedName)': valuePer100g(raw=\(rawVal), rounded=\(val)), constraint=\(goal.constraint)")

                    switch goal.constraint {
                    case .min(let v):
                        let t = SmartFoodSearch3.roundToSingleDecimal(v)
                        if val < t { passesNutrients = false }

                    case .max(let v):
                        let t = SmartFoodSearch3.roundToSingleDecimal(v)
                        if val > t { passesNutrients = false }

                    case .strictMin(let v):
                        let t = SmartFoodSearch3.roundToSingleDecimal(v)
                        if val <= t { passesNutrients = false }

                    case .strictMax(let v):
                        let t = SmartFoodSearch3.roundToSingleDecimal(v)
                        if val >= t { passesNutrients = false }

                    case .range(let l, let h):
                        let lo = SmartFoodSearch3.roundToSingleDecimal(l)
                        let hi = SmartFoodSearch3.roundToSingleDecimal(h)
                        if val < lo || val > hi { passesNutrients = false }

                    case .notEqual(let v):
                        let t = SmartFoodSearch3.roundToSingleDecimal(v)
                        if val == t { passesNutrients = false }

                    case .high:
                        // "high X" – 0 не минава така или иначе
                        if val <= 0 { passesNutrients = false }

                    case .low, .lowest, .highest:
                        // "low X" – позволяваме и 0 тук
                        break
                    }

                    if !passesNutrients { break }
                }
                if !passesNutrients { continue }
                
                itemsToRank.append(item)
            }
            
            let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            let simpleRawIsSingleWord = !simpleRawQuery.contains(" ")
            let rawWords = searchQuery
                .lowercased()
                .components(separatedBy: allowedChars.inverted)
                .filter { !$0.isEmpty }
            let validRawWords: [String] = rawWords.filter { raw in effectiveTextTokens.contains(Tokenizer.processWord(raw)) }
            let rawCleanQuery = validRawWords.joined(separator: " ")
            let rawPaddedQuery = " " + rawCleanQuery + " "
            var rankedItems: [(
                item: CompactFoodItem,
                score: Double,
                ayurvedaScore: Double
            )] = []
            
            for (index, item) in itemsToRank.enumerated() {
                if index % 500 == 0 && Task.isCancelled {
                    return (
                        [],
                        intent,
                        [],
                        forceShowPH,
                        foodsWithoutPhExcluded
                    )
                }
                var score = 100.0
                let nameLower = item.lowercasedName
                let paddedName = item.paddedLowercasedName
                
                if !simpleRawQuery.isEmpty && simpleRawQuery.count >= 2 {
                    if simpleRawIsSingleWord {
                        if nameLower == simpleRawQuery { score += 4000.0 }
                        else if nameLower.hasPrefix(simpleRawQuery + " ") || nameLower.hasPrefix(simpleRawQuery + ",") { score += 3500.0 }
                        else if nameLower.hasPrefix(simpleRawQuery) { score += 3000.0 }
                        else if nameLower.contains(simpleRawQuery) { score += 1500.0 }
                    } else if nameLower.contains(simpleRawQuery) { score += 1500.0 }
                }
                
                if !effectiveTextTokens.isEmpty, !rawCleanQuery.isEmpty {
                    if nameLower == rawCleanQuery { score += 3000.0 }
                    else if nameLower.hasPrefix(rawCleanQuery + " ") || nameLower.hasPrefix(rawCleanQuery + ",") { score += 2500.0 }
                    else if paddedName.contains(rawPaddedQuery) { score += 2000.0 }
                    else if nameLower.hasPrefix(rawCleanQuery) { score += 500.0 }
                    var matches = 0
                    for term in effectiveTextTokens {
                        if paddedName.contains(" " + term + " ") { score += 200.0; matches += 1 }
                        else if nameLower.contains(term) { score += 50.0; matches += 1 }
                    }
                    if matches > 0 { score -= Double(item.searchTokens.count) * 5.0 }
                }
                
                for (idx, goal) in intent.nutrientGoals.enumerated() {
                    let val: Double = (item.referenceWeightG > 0) ? (item.value(for: goal.nutrient) / item.referenceWeightG) * 100.0 : 0.0
                    let max = maxValues[goal.nutrient] ?? 1.0
                    let normalized = val / (max == 0 ? 1 : max)
                    let weight = 50.0 / pow(2.0, Double(idx))
                    switch goal.constraint {
                    case .high, .min, .strictMin: score += normalized * weight
                    case .low, .max, .strictMax: score += (1.0 - normalized) * weight
                    default: score += weight
                    }
                }
                let ayurvedaScore: Double
                if let ayurveda = item.ayurvedaMetadata {
                    ayurvedaScore = AyurvedaSearchRanker.score(
                        ayurveda,
                        filters: ayurvedaFilters,
                        constraints: intent.ayurvedaFacetConstraints,
                        temporalContext: temporalContext,
                        constitutionTarget: constitutionTarget
                    )
                    score += ayurvedaScore
                } else {
                    ayurvedaScore = 0
                }
                rankedItems.append((item, score, ayurvedaScore))
            }
            
            let hasAyurvedaRequest = ayurvedaFilters.isActive
                || !intent.ayurvedaFacetConstraints.isEmpty
            let sortedResults: [Int]
            if let phLimit = intent.phConstraint {
                // Тук се случва сортирането по pH!
                let preferLowPH =
                    PhSearchSemantics.prefersLowValues(for: phLimit)
                let primaryGoal = intent.nutrientGoals.first
                sortedResults = rankedItems.sorted { lhs, rhs in
                    // 1. pH Сортиране
                    if lhs.item.ph != rhs.item.ph {
                        return preferLowPH ? (lhs.item.ph < rhs.item.ph) : (lhs.item.ph > rhs.item.ph)
                    }
                    // 2. Вторично сортиране по нутриент (ако има)
                    if let g = primaryGoal {
                        let leftVal = lhs.item.value(for: g.nutrient); let rightVal = rhs.item.value(for: g.nutrient)
                        let preferLowValues: Bool = {
                            switch g.constraint {
                            case .low, .max, .strictMax: return true
                            default: return false
                            }
                        }()
                        if leftVal != rightVal { return preferLowValues ? (leftVal < rightVal) : (leftVal > rightVal) }
                    }
                    // 3. Третично сортиране по Score
                    if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                    // 4. Азбучно
                    return lhs.item.lowercasedName < rhs.item.lowercasedName
                }.map { $0.item.id }
            } else if let primaryGoal = intent.nutrientGoals.first {
                let preferLowValues: Bool = {
                    switch primaryGoal.constraint {
                    case .low, .max, .strictMax: return true
                    default: return false
                    }
                }()
                sortedResults = rankedItems.sorted { lhs, rhs in
                    let leftVal = lhs.item.value(for: primaryGoal.nutrient); let rightVal = rhs.item.value(for: primaryGoal.nutrient)
                    if leftVal != rightVal { return preferLowValues ? (leftVal < rightVal) : (leftVal > rightVal) }
                    if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                    return lhs.item.lowercasedName < rhs.item.lowercasedName
                }.map { $0.item.id }
            } else {
                sortedResults = rankedItems.sorted { lhs, rhs in
                    if hasAyurvedaRequest,
                       lhs.item.ayurvedaMetadata != nil,
                       rhs.item.ayurvedaMetadata != nil,
                       abs(lhs.ayurvedaScore - rhs.ayurvedaScore) > 0.001 {
                        return lhs.ayurvedaScore > rhs.ayurvedaScore
                    }
                    if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                    return lhs.item.lowercasedName < rhs.item.lowercasedName
                }.map { $0.item.id }
            }

            let finalResults: [Int]
            if hasAyurvedaRequest {
                let profiled = sortedResults.filter {
                    compactMap[$0]?.ayurvedaMetadata != nil
                }
                let unprofiled = sortedResults.filter {
                    compactMap[$0]?.ayurvedaMetadata == nil
                }
                var interleaved: [Int] = []
                interleaved.reserveCapacity(sortedResults.count)
                var profiledIndex = 0
                var unprofiledIndex = 0
                while profiledIndex < profiled.count
                    || unprofiledIndex < unprofiled.count {
                    let nextProfiled = min(
                        profiledIndex + 30,
                        profiled.count
                    )
                    let nextUnprofiled = min(
                        unprofiledIndex + 10,
                        unprofiled.count
                    )
                    interleaved.append(
                        contentsOf: profiled[profiledIndex..<nextProfiled]
                    )
                    interleaved.append(
                        contentsOf: unprofiled[unprofiledIndex..<nextUnprofiled]
                    )
                    profiledIndex = nextProfiled
                    unprofiledIndex = nextUnprofiled
                }
                finalResults = interleaved
            } else {
                finalResults = sortedResults
            }
            
            return (
                finalResults,
                intent,
                effectiveTextTokens,
                forceShowPH,
                foodsWithoutPhExcluded
            )
        }
    // MARK: - Fuzzy / Semantic Helpers
    
    nonisolated private func findPrefixMatches(for term: String, vocab: [String]) async -> [String] {
        let len = term.count
        guard len > 0 else { return [] }
        let matches = vocab
            .filter { $0.hasPrefix(term) }
            .sorted { ($0.count != $1.count) ? $0.count < $1.count : $0 < $1 }
        let limit = (len == 1) ? 80 : (len == 2) ? 200 : (len == 3) ? 80 : 40
        return Array(matches.prefix(limit))
    }
    
    nonisolated private func findSemanticNeighbors(for term: String, vocab: Set<String>, maxCount: Int = 20) -> [String] {
        guard term.count >= 3, let embedding = smartFoodSearchEmbedding else { return [] }
        return embedding
            .neighbors(for: term, maximumCount: maxCount)
            .map { $0.0 }
            .filter { vocab.contains($0) }
    }
    
    nonisolated private func findClosestWords(to term: String, vocab: [String]) async -> [String] {
        vocab.filter { word in
            if abs(word.count - term.count) > 2 { return false }
            let dist = SmartFoodSearch3.levenshteinDistance(term, word)
            return (term.count < 4) ? (dist == 0) : (term.count <= 6) ? (dist <= 1) : (dist <= 2)
        }
    }
    
    nonisolated private static func levenshteinDistance(_ s: String, _ t: String) -> Int {
        s.levenshteinDistance(to: t)
    }
    
    // MARK: - Data Loading
    @MainActor
    func loadData() {
        Task { await loadDataAndWait() }
    }

    /// Makes the search index available to callers that need to issue a query
    /// immediately after presenting their UI.
    @MainActor
    @discardableResult
    func prepareForSearch() async -> Bool {
        let store = SearchIndexStore.shared
        if store.compactFoods.isEmpty {
            isLoading = true
            await store.ensureLoaded(container: container)
        }
        if allFoods.isEmpty || loadedIndexRevision != store.revision {
            applyLoadedIndex()
        }
        if isLoading {
            isLoading = false
        }

        return !allFoods.isEmpty
    }

    @MainActor
    private func loadDataAndWait() async {
        await prepareForSearch()

        if lastCanonicalQuery.isEmpty,
           lastActiveFilters.isEmpty,
           displayedResults.isEmpty {
            showDefaultResultsIfPossible()
        }

    }

    @MainActor
    private func applyLoadedIndex() {
        let store = SearchIndexStore.shared
        let didChange = loadedIndexRevision != store.revision
        allFoods = store.compactFoods
        compactMap = store.compactMap
        invertedIndex = store.invertedIndex
        ayurvedaFacetIndex = store.ayurvedaFacetIndex
        vocabulary = store.vocabulary
        maxNutrientValues = store.maxNutrientValues
        nutrientRankings = store.nutrientRankings
        loadedIndexRevision = store.revision
        if didChange {
            // Force the next request to run even when its text and filters are
            // identical to the request made before an item was edited.
            lastCanonicalQuery = "\u{0}"
        }
    }
    
    // MARK: - Numeric rounding helper (single decimal place)
    nonisolated private static func roundToSingleDecimal(_ x: Double) -> Double {
        (x * 10).rounded() / 10
    }

    // MARK: - Numeric Constraint Parsing (regex engine)
    
    nonisolated private static func parseNumericNutrientConstraints(from query: String) -> [NutrientGoal] {
        var lower = query.lowercased()
        
        // REPLACEMENT LOGIC:
        let regexReplacements: [(String, String)] = [
            // 1. Longest phrases – explicitly inclusive
            (#"\bless\s+than\s+or\s+equal\s+to\b"#, " <= "),
            (#"\bno\s+more\s+than\b"#, " <= "),
            (#"\bat\s+most\b"#, " <= "),
            (#"\bmaximum\b"#, " <= "),
            (#"\bgreater\s+than\s+or\s+equal\s+to\b"#, " >= "),
            (#"\bat\s+least\b"#, " >= "),
            (#"\bminimum\b"#, " >= "),
            
            // 2. Standard phrases – plain "less than"/"more than" are STRICT
            (#"\bless\s+than\b"#, " < "),
            (#"\bfewer\s+than\b"#, " < "),
            (#"\blower\s+than\b"#, " < "),
            (#"\bmore\s+than\b"#, " > "),
            (#"\bgreater\s+than\b"#, " > "),
            (#"\bhigher\s+than\b"#, " > "),
            
            // 3. Short colloquialisms
            // "under/below/less/fewer/lower" → strict "<"
            (#"\bunder\b"#, " < "),
            (#"\bbelow\b"#, " < "),
            (#"\bless\b"#, " < "),
            (#"\bfewer\b"#, " < "),
            (#"\blower\b"#, " < "),
            // "min" / "max" keep inclusive meaning
            (#"\bmin\b"#, " >= "),
            (#"\bmax\b"#, " <= "),
            // "over/above/exceeds/more/greater/higher" → strict ">"
            (#"\bover\b"#, " > "),
            (#"\babove\b"#, " > "),
            (#"\bexceeds\b"#, " > "),
            (#"\bmore\b"#, " > "),
            (#"\bgreater\b"#, " > "),
            (#"\bhigher\b"#, " > ")
        ]
        
        for (pattern, template) in regexReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: lower.utf16.count)
                lower = regex.stringByReplacingMatches(in: lower, options: [], range: range, withTemplate: template)
            }
        }
        
        print("🔍 [SmartSearch] Text for Regex: '\(lower)'")
        
        var goals: [NutrientGoal] = []
        let ns = lower as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        
        var processedRanges: [NSRange] = []
        func rangesOverlap(_ a: NSRange, _ b: NSRange) -> Bool { return NSIntersectionRange(a, b).length > 0 }
        func isProcessed(_ range: NSRange) -> Bool { return processedRanges.contains(where: { rangesOverlap($0, range) }) }
        func markProcessed(_ range: NSRange) { processedRanges.append(range) }
        func subjectLooksComposite(_ name: String) -> Bool {
            let s = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return s.contains(" and ") || s.contains(" or ")
        }
        
        @discardableResult
        func appendGoal(nutrientPhrase: String, opString: String?, value: Double, unitString: String?) -> Bool {
            let trimmedName = nutrientPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            if ConstraintQueryBoundary(trimmedName).containsToken("ph") {
                return false
            }
            guard let nutrient = SearchKnowledgeBase.shared.bestNutrientMatch(in: trimmedName) else { return false }
            
            let normalizedValue = normalizedNumericValue(value, unitString: unitString, for: nutrient)
            let op = opString ?? ">="
            
            let constraint: ConstraintValue
            switch op {
            case ">", "&gt;": constraint = .strictMin(normalizedValue)
            case ">=", "&gt=","&gt;=": constraint = .min(normalizedValue)
            case "<", "&lt;": constraint = .strictMax(normalizedValue)
            case "<=", "&lt=","&lt;=": constraint = .max(normalizedValue)
            case "!=": constraint = .notEqual(normalizedValue)
            case "=": constraint = .range(normalizedValue, normalizedValue)
            default: constraint = .min(normalizedValue)
            }
            goals.append(NutrientGoal(nutrient: nutrient, constraint: constraint))
            return true
        }
        
        // 1) PRE-DOUBLE constraint
        if let preDoubleRegex = try? NSRegularExpression(
            pattern: #"(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?\s*(?:and)?\s*(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?\s+([a-z0-9_\s:]+)"#,
            options: []
        ) {
            let matches = preDoubleRegex.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 8 {
                if isProcessed(match.range) { continue }
                
                let nutrientNameRaw = ns.substring(with: match.range(at: 7))
                if subjectLooksComposite(nutrientNameRaw) { continue }
                
                var didAppend = false
                
                let op1   = ns.substring(with: match.range(at: 1))
                let val1  = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let unit1 = (match.range(at: 3).location != NSNotFound) ? ns.substring(with: match.range(at: 3)) : nil
                let op2   = ns.substring(with: match.range(at: 4))
                let val2  = Double(ns.substring(with: match.range(at: 5))) ?? 0
                let unit2 = (match.range(at: 6).location != NSNotFound) ? ns.substring(with: match.range(at: 6)) : unit1
                let nutrientName = nutrientNameRaw
                
                print("🔍 [SmartSearch] Found PRE-DOUBLE constraint: \(op1) \(val1) \(unit1 ?? "") ... \(op2) \(val2) \(unit2 ?? "") ... \(nutrientName)")
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op1, value: val1, unitString: unit1) || didAppend
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op2, value: val2, unitString: unit2) || didAppend
                if didAppend {
                    markProcessed(match.range)
                }
            }
        }
        
        // 2) SANDWICH constraint
        if let sandwichRegex = try? NSRegularExpression(
            pattern: #"(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?\s+([a-z0-9_\s:]+?)\s+(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?"#,
            options: []
        ) {
            let matches = sandwichRegex.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 8 {
                if isProcessed(match.range) { continue }
                
                let nutrientNameRaw = ns.substring(with: match.range(at: 4))
                if subjectLooksComposite(nutrientNameRaw) { continue }
                
                var didAppend = false
                
                let op1   = ns.substring(with: match.range(at: 1))
                let val1  = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let unit1 = (match.range(at: 3).location != NSNotFound) ? ns.substring(with: match.range(at: 3)) : nil
                let nutrientName = nutrientNameRaw
                let op2   = ns.substring(with: match.range(at: 5))
                let val2  = Double(ns.substring(with: match.range(at: 6))) ?? 0
                let unit2 = (match.range(at: 7).location != NSNotFound) ? ns.substring(with: match.range(at: 7)) : unit1
                
                print("🔍 [SmartSearch] Found SANDWICH constraint: \(op1) \(val1) \(unit1 ?? "") ... \(nutrientName) ... \(op2) \(val2) \(unit2 ?? "")")
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op1, value: val1, unitString: unit1) || didAppend
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op2, value: val2, unitString: unit2) || didAppend
                if didAppend {
                    markProcessed(match.range)
                }
            }
        }
        
        // 3) POST-DOUBLE
        if let postRegex = try? NSRegularExpression(
            pattern: #"([a-z0-9_\s:]+?)\s+(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?\s*(?:and)?\s*(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?"#,
            options: []
        ) {
            let matches = postRegex.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 8 {
                if isProcessed(match.range) { continue }
                
                let nutrientNameRaw = ns.substring(with: match.range(at: 1))
                if subjectLooksComposite(nutrientNameRaw) { continue }
                
                var didAppend = false
                
                let nutrientName = nutrientNameRaw
                let op1   = ns.substring(with: match.range(at: 2))
                let val1  = Double(ns.substring(with: match.range(at: 3))) ?? 0
                let unit1 = (match.range(at: 4).location != NSNotFound) ? ns.substring(with: match.range(at: 4)) : nil
                let op2   = ns.substring(with: match.range(at: 5))
                let val2  = Double(ns.substring(with: match.range(at: 6))) ?? 0
                let unit2 = (match.range(at: 7).location != NSNotFound) ? ns.substring(with: match.range(at: 7)) : unit1
                
                print("🔍 [SmartSearch] Found POST constraint: \(nutrientName) ... \(op1) \(val1) \(unit1 ?? "") ... \(op2) \(val2) \(unit2 ?? "")")
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op1, value: val1, unitString: unit1) || didAppend
                didAppend = appendGoal(nutrientPhrase: nutrientName, opString: op2, value: val2, unitString: unit2) || didAppend
                if didAppend {
                    markProcessed(match.range)
                }
            }
        }
        
        // 4) Loose trailing comparator
        let loosePattern = #"([a-z0-9_\s:]+?)\s*(<=|>=|!=|=|<|>)\s*$"#
        if let looseRegex = try? NSRegularExpression(pattern: loosePattern, options: []) {
            let matches = looseRegex.matches(in: lower, options: [], range: fullRange)
            if let match = matches.first, match.numberOfRanges >= 3 {
                if !isProcessed(match.range) {
                    let rawN = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let op   = ns.substring(with: match.range(at: 2))
                    if !rawN.isEmpty {
                        let defaultValue: Double = (op.contains(">")) ? 0 : 1_000_000
                        let didAppend = appendGoal(nutrientPhrase: rawN, opString: op, value: defaultValue, unitString: nil)
                        if didAppend {
                            markProcessed(match.range)
                        }
                    }
                }
            }
        }
        
        // 5) Range with dash
        if let rangeRegex1 = try? NSRegularExpression(
            pattern: #"([a-z0-9_\s:]+?)\s+([0-9]+(?:\.[0-9]+)?)\s*[-–]\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?"#,
            options: []
        ) {
            let matches = rangeRegex1.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 5 {
                if isProcessed(match.range) { continue }
                markProcessed(match.range)
                
                let rawNutrient = ns.substring(with: match.range(at: 1))
                let lowS  = ns.substring(with: match.range(at: 2))
                let highS = ns.substring(with: match.range(at: 3))
                let unitS = (match.range(at: 4).location != NSNotFound) ? ns.substring(with: match.range(at: 4)) : nil
                if let low = Double(lowS),
                   let high = Double(highS),
                   let nutrient = SearchKnowledgeBase.shared.bestNutrientMatch(in: rawNutrient.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let lowNorm  = normalizedNumericValue(low, unitString: unitS, for: nutrient)
                    let highNorm = normalizedNumericValue(high, unitString: unitS, for: nutrient)
                    goals.append(NutrientGoal(nutrient: nutrient, constraint: .range(lowNorm, highNorm)))
                }
            }
        }
        
        // 6) Op, value, nutrient
        if let opRegex1 = try? NSRegularExpression(
            pattern: #"(<=|>=|!=|=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?\s+([a-z0-9_\s:]+)"#,
            options: []
        ) {
            let matches = opRegex1.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 5 {
                if isProcessed(match.range) { continue }
                let opS   = ns.substring(with: match.range(at: 1))
                let valS  = ns.substring(with: match.range(at: 2))
                let unitS = (match.range(at: 3).location != NSNotFound) ? ns.substring(with: match.range(at: 3)) : nil
                let rawN  = ns.substring(with: match.range(at: 4))
                if let val = Double(valS) {
                    let didAppend = appendGoal(nutrientPhrase: rawN, opString: opS, value: val, unitString: unitS)
                    if didAppend {
                        markProcessed(match.range)
                    }
                }
            }
        }
        
        // 7) Nutrient, op, value
        if let opRegex2 = try? NSRegularExpression(
            pattern: #"([a-z0-9_\s:]+?)\s*(<=|>=|!=|=|<|>)\s*([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)?"#,
            options: []
        ) {
            let matches = opRegex2.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 5 {
                if isProcessed(match.range) { continue }
                let rawN  = ns.substring(with: match.range(at: 1))
                let opS   = ns.substring(with: match.range(at: 2))
                let valS  = ns.substring(with: match.range(at: 3))
                let unitS = (match.range(at: 4).location != NSNotFound) ? ns.substring(with: match.range(at: 4)) : nil
                if let val = Double(valS) {
                    let didAppend = appendGoal(nutrientPhrase: rawN, opString: opS, value: val, unitString: unitS)
                    if didAppend {
                        markProcessed(match.range)
                    }
                }
            }
        }
        
        // 8) Direct: nutrient value unit
        if let directRegex1 = try? NSRegularExpression(
            pattern: #"([a-z0-9_\s:]+?)\s+([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Zµ%/]+)"#,
            options: []
        ) {
            let matches = directRegex1.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 4 {
                if isProcessed(match.range) { continue }
                let rawN  = ns.substring(with: match.range(at: 1))
                let valS  = ns.substring(with: match.range(at: 2))
                let unitS = ns.substring(with: match.range(at: 3))
                if let val = Double(valS) {
                    let didAppend = appendGoal(nutrientPhrase: rawN, opString: nil, value: val, unitString: unitS)
                    if didAppend {
                        markProcessed(match.range)
                    }
                }
            }
        }
        
        // 9) COMPARATOR ONLY (Missing Value)
        if let danglingOpRegex = try? NSRegularExpression(
            pattern: #"(<=|>=|!=|=|<|>)\s*([a-z0-9_\s:]+)"#,
            options: []
        ) {
            let matches = danglingOpRegex.matches(in: lower, options: [], range: fullRange)
            for match in matches where match.numberOfRanges >= 3 {
                if isProcessed(match.range) { continue }

                let op = ns.substring(with: match.range(at: 1))
                let rawN = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)

                guard !rawN.isEmpty, Double(rawN) == nil else { continue }

                var didAppend = false

                if let nutrient = SearchKnowledgeBase.shared.bestNutrientMatch(in: rawN) {
                    let constraint: ConstraintValue
                    switch op {
                    case "<", "<=":
                        constraint = .low
                    case ">", ">=", "=", "!=":
                        constraint = .high
                    default:
                        constraint = .high
                    }
                    goals.append(NutrientGoal(nutrient: nutrient, constraint: constraint))
                    didAppend = true
                }
                if didAppend {
                    markProcessed(match.range)
                }
            }
        }
        
        // Merge logic (Min/Max consolidation)
        if !goals.isEmpty {
            var merged: [NutrientGoal] = []
            var byNutrient: [NutrientType: [NutrientGoal]] = [:]
            
            for g in goals { byNutrient[g.nutrient, default: []].append(g) }
            
            for (nutrient, list) in byNutrient {
                var minVal: Double?; var maxVal: Double?; var others: [NutrientGoal] = []
                for g in list {
                    switch g.constraint {
                    case .min(let v): minVal = max(minVal ?? v, v)
                    case .max(let v): maxVal = min(maxVal ?? v, v)
                    case .strictMin(let v): minVal = max(minVal ?? v + 0.0001, v + 0.0001)
                    case .strictMax(let v): maxVal = min(maxVal ?? v - 0.0001, v - 0.0001)
                    default: others.append(g)
                    }
                }
                if let lo = minVal, let hi = maxVal { others.append(NutrientGoal(nutrient: nutrient, constraint: .range(lo, hi))) }
                else if let lo = minVal { others.append(NutrientGoal(nutrient: nutrient, constraint: .min(lo))) }
                else if let hi = maxVal { others.append(NutrientGoal(nutrient: nutrient, constraint: .max(hi))) }
                
                merged.append(contentsOf: others)
            }
            goals = merged
        }
        
        return goals
    }
    
    
    nonisolated private static func mergeNumericGoals(_ numericGoals: [NutrientGoal], into existing: [NutrientGoal]) -> [NutrientGoal] {
        var result = existing
        
        let nutrientsWithNewConstraints = Set(numericGoals.map { $0.nutrient })
        
        if !nutrientsWithNewConstraints.isEmpty {
            result.removeAll { nutrientsWithNewConstraints.contains($0.nutrient) }
        }
        
        result.append(contentsOf: numericGoals)
        
        return result
    }

    nonisolated private static func orderedDisplayNutrients(
        in query: String,
        goalGroups: [[NutrientGoal]]
    ) -> [NutrientType] {
        var seen = Set<NutrientType>()
        let candidates = goalGroups
            .flatMap { $0 }
            .map(\.nutrient)
            .filter { seen.insert($0).inserted }
        guard candidates.count > 1 else { return candidates }

        let lowerQuery = query.lowercased()
        let aliases = SearchKnowledgeBase.shared.nutrientMap

        func isWordCharacter(_ character: Character) -> Bool {
            character.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0)
            }
        }

        func firstBoundaryPosition(of phrase: String) -> Int? {
            var searchStart = lowerQuery.startIndex
            while searchStart < lowerQuery.endIndex,
                  let range = lowerQuery.range(
                    of: phrase.lowercased(),
                    range: searchStart..<lowerQuery.endIndex
                  ) {
                let startsAtBoundary =
                    range.lowerBound == lowerQuery.startIndex
                    || !isWordCharacter(
                        lowerQuery[lowerQuery.index(before: range.lowerBound)]
                    )
                let endsAtBoundary =
                    range.upperBound == lowerQuery.endIndex
                    || !isWordCharacter(lowerQuery[range.upperBound])
                if startsAtBoundary, endsAtBoundary {
                    return lowerQuery.distance(
                        from: lowerQuery.startIndex,
                        to: range.lowerBound
                    )
                }
                searchStart = range.upperBound
            }
            return nil
        }

        var positions: [NutrientType: Int] = [:]
        for nutrient in candidates {
            let position = aliases
                .lazy
                .filter { $0.value == nutrient }
                .compactMap { firstBoundaryPosition(of: $0.key) }
                .min()
            if let position {
                positions[nutrient] = position
            }
        }
        let fallbackOrder = Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map {
                ($0.element, $0.offset)
            }
        )

        return candidates.sorted { left, right in
            switch (positions[left], positions[right]) {
            case let (.some(leftPosition), .some(rightPosition)):
                if leftPosition != rightPosition {
                    return leftPosition < rightPosition
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
            return fallbackOrder[left, default: 0] < fallbackOrder[right, default: 0]
        }
    }
    
    // MARK: - Numeric constraint splitting helper
    
    nonisolated private static func splitNumericConstraintSegments(in query: String) -> [String] {
        let lower = query.lowercased()
        
        let pattern = #"(?<![a-z0-9])(less than|more than|greater than|at least|at most|no more than|no less than|under|below|over|>=|<=|>|<|≥|≤)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [query]
        }
        
        let ns = lower as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: lower, options: [], range: fullRange)
        
        if matches.isEmpty {
            return [query]
        }
        
        var segments: [String] = []
        var lastIndex = 0
        
        for match in matches {
            let start = match.range.location
            if start > lastIndex {
                let r = NSRange(location: lastIndex, length: start - lastIndex)
                let seg = ns.substring(with: r)
                let trimmed = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(trimmed)
                }
            }
            lastIndex = start
        }
        
        if lastIndex < ns.length {
            let r = NSRange(location: lastIndex, length: ns.length - lastIndex)
            let seg = ns.substring(with: r)
            let trimmed = seg.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(trimmed)
            }
        }
        
        return segments
    }
    
    // MARK: - High-level numeric constraint entry point
    
    nonisolated private static func parseNumericNutrientConstraintsFromQuery(_ query: String) -> [NutrientGoal] {
        // 0) First, try the full-query parser directly.
        let directGoals = parseNumericNutrientConstraints(from: query)
        if !directGoals.isEmpty {
            return directGoals
        }
        
        // 1) Segmented strategy
        let segments = splitNumericConstraintSegments(in: query)
        
        if segments.count == 1 {
            return []
        }
        
        var allGoals: [NutrientGoal] = []
        
        for segment in segments {
            let goals = parseNumericNutrientConstraints(from: segment)
            if !goals.isEmpty {
                allGoals.append(contentsOf: goals)
            }
        }
        
        guard !allGoals.isEmpty else { return [] }
        
        var unique: [NutrientGoal] = []
        for g in allGoals {
            if !unique.contains(where: {
                $0.nutrient == g.nutrient &&
                String(describing: $0.constraint) == String(describing: g.constraint)
            }) {
                unique.append(g)
            }
        }
        return unique
    }
    
    // MARK: - Canonical query helper
    
    /// Normalises a raw user query by lowercasing and collapsing whitespace.
    nonisolated private static func canonicalQuery(from raw: String) -> String {
        let lower = raw.lowercased()
        let parts = lower
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
    
    // MARK: - Dynamic "OR" Variant Expansion
    /// Breaks down a query containing "or" into logical sub-queries.
    /// Example: "pork with rice or tomatoes" ->
    /// ["pork with rice or tomatoes", "pork with rice", "pork with tomatoes"]
    nonisolated private static func expandOrVariants(_ query: String) -> [String] {
        let lower = query.lowercased()
        
        // Always try the original query first so literal matches (e.g. USDA names)
        // are highly ranked if they exist.
        var variants: [String] = [lower]
        
        let words = lower
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard let orIndex = words.firstIndex(of: "or"),
              orIndex > 0,
              orIndex < words.count - 1 else {
            return variants
        }
        
        let wordBefore = words[orIndex - 1]
        let wordAfter  = words[orIndex + 1]
        
        let prefixTokens = words[0..<(orIndex - 1)]
        let suffixTokens = words[(orIndex + 2)...]
        
        let prefixStr = prefixTokens.joined(separator: " ")
        let suffixStr = suffixTokens.joined(separator: " ")
        
        func build(middle: String) -> String {
            var parts: [String] = []
            if !prefixStr.isEmpty { parts.append(prefixStr) }
            parts.append(middle)
            if !suffixStr.isEmpty { parts.append(suffixStr) }
            return parts.joined(separator: " ")
        }
        
        variants.append(build(middle: wordBefore))
        variants.append(build(middle: wordAfter))
        
        return variants
    }
}

extension SearchKnowledgeBase {
    /// Returns the canonical unit (e.g. "g", "mg", "µg") for a nutrient.
    /// Delegates to FoodItem so there is a single source of truth for units.
    func defaultUnit(for nutrient: NutrientType) -> String {
        return FoodItem.canonicalUnit(for: nutrient)
    }
}

extension SmartFoodSearch3 {
    /// Centralised human-readable display name for each nutrient type.
    nonisolated static func displayName(for nutrient: NutrientType) -> String {
        switch nutrient {
        case .totalFat:        return "Fat"
        case .totalSugar:      return "Sugar"
        case .energy:          return "Еnergy"

        // Vitamins
        case .vitaminA:        return "Vit A"
        case .vitaminC:        return "Vit C"
        case .vitaminD:        return "Vit D"
        case .vitaminE:        return "Vit E"
        case .vitaminK:        return "Vit K"
        case .thiamin:         return "Vit B1"
        case .riboflavin:      return "Vit B2"
        case .niacin:          return "Vit B3"
        case .pantothenicAcid: return "Vit B5"
        case .vitaminB6:       return "Vit B6"
        case .vitaminB12:      return "Vit B12"
        case .folateTotal:     return "Folate"
        case .folateDFE:       return "Folate DFE"
        case .folicAcid:       return "Folic Acid"
        case .folateFood:      return "Food Folate"
        case .luteinZeaxanthin: return "Lutein + Zeax."
        case .lycopene:        return "Lycopene"
        case .caffeine:        return "Caffeine"
        case .cholesterol:     return "Cholesterol"
        case .alphaCarotene:     return "α-Carotene"
        case .betaCarotene:      return "β-Carotene"
        case .betaCryptoxanthin: return "β-Cryptoxanthin"
        default:
            // Fallback: pretty-print the raw value
            return nutrient.rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    /// Instance convenience for views that hold an engine instance.
    @MainActor
    func displayName(for nutrient: NutrientType) -> String {
        Self.displayName(for: nutrient)
    }
}

extension SmartFoodSearch3 {
    /// Runs the full SmartFoodSearch3 pipeline and returns results as an array,
    /// without touching `displayedResults`. Limit defaults to 20.
    @MainActor
    func searchResults(
        query rawQuery: String,
        activeFilters: Set<NutrientType> = [],
        quickAgeMonths: Double? = nil,
        forcePhDisplay: Bool = false,
        isFavoritesOnly: Bool = false,
        isRecipesOnly: Bool = false,
        isMenusOnly: Bool = false,
        searchMode: SearchMode? = nil,
        profile: Profile? = nil,
        excludedFoodIDs: Set<Int> = [],
        ayurvedaFilters: AyurvedaSearchFilters = .empty,
        phSortOrder: PhSortOrder? = nil,
        limit: Int = 20
    ) async -> [FoodItem] {
        // Make sure index is loaded (this may populate allFoods / invertedIndex / etc.)
        if allFoods.isEmpty {
            await loadDataAndWait()
        }

        let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)

        // Build profile constraints just like in performSearch(...)
        var profileConstraints: ProfileSearchConstraints? = nil
        let constitutionTarget: AyurvedaDoshaDistribution?
        if let p = profile {
            profileConstraints = ProfileSearchConstraints(
                ageInMonths: p.ageInMonths,
                avoidedAllergens: Set(p.allergens.map { $0.rawValue })
            )
            constitutionTarget = AyurvedaConstitutionStore
                .record(for: p.id)?
                .target()
        } else {
            constitutionTarget = nil
        }

        // Snapshot lightweight state (same pattern as performSearch)
        let snapshotAllFoods = allFoods
        let snapshotMap = compactMap
        let snapshotIndex = invertedIndex
        let snapshotFacetIndex = ayurvedaFacetIndex
        let snapshotVocab = vocabulary
        let snapshotMaxValues = maxNutrientValues
        let snapshotRankings = nutrientRankings
        let snapshotExcludedIDs = excludedFoodIDs

        // Run the full search logic pipeline.
        let (resultIDs, _, _, _, _) = await self.runSearchLogic(
            query: canonicalQuery,
            activeFilters: activeFilters,
            compactMap: snapshotMap,
            allFoods: snapshotAllFoods,
            maxValues: snapshotMaxValues,
            invertedIndex: snapshotIndex,
            ayurvedaFacetIndex: snapshotFacetIndex,
            vocabulary: snapshotVocab,
            nutrientRankings: snapshotRankings,
            quickAgeMonths: quickAgeMonths,
            forcePhDisplay: forcePhDisplay,
            isFavoritesOnly: isFavoritesOnly,
            isRecipesOnly: isRecipesOnly,
            isMenusOnly: isMenusOnly,
            searchMode: searchMode,
            profileConstraints: profileConstraints,
            excludedFoodIDs: snapshotExcludedIDs,
            ayurvedaFilters: ayurvedaFilters,
            temporalContext: AyurvedaSearchTemporalContext.current(),
            constitutionTarget: constitutionTarget,
            phSortOrder: phSortOrder,
            container: self.container
        )

        // Apply limit
        let safeLimit = max(0, limit)
        let limitedIDs = Array(resultIDs.prefix(safeLimit))
        guard !limitedIDs.isEmpty else { return [] }

        // Fetch FoodItem objects for these IDs (preserving ranking order)
        let context = container.mainContext
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { limitedIDs.contains($0.id) }
        )

        do {
            let fetched = try context.fetch(descriptor)
            let idMap = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let sortedItems = limitedIDs.compactMap { idMap[$0] }
            return sortedItems
        } catch {
            print("❌ [SmartSearch] Error fetching limited results: \(error)")
            return []
        }
    }
}

extension SmartFoodSearch3 {
    /// Runs the search pipeline but returns Sendable `CompactFoodItem` structs
    /// instead of non-Sendable `FoodItem` objects. Safe for background tasks.
    @MainActor
    func searchCompact(
        query rawQuery: String,
        searchMode: SearchMode? = nil,
        limit: Int = 20
    ) async -> [CompactFoodItem] {
        // Ensure index is loaded
        if allFoods.isEmpty {
            await loadDataAndWait()
        }

        let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)

        // Snapshot lightweight state
        let snapshotAllFoods = allFoods
        let snapshotMap = compactMap
        let snapshotIndex = invertedIndex
        let snapshotFacetIndex = ayurvedaFacetIndex
        let snapshotVocab = vocabulary
        let snapshotMaxValues = maxNutrientValues
        let snapshotRankings = nutrientRankings
        
        // Run search logic
        let (resultIDs, _, _, _, _) = await self.runSearchLogic(
            query: canonicalQuery,
            activeFilters: [],
            compactMap: snapshotMap,
            allFoods: snapshotAllFoods,
            maxValues: snapshotMaxValues,
            invertedIndex: snapshotIndex,
            ayurvedaFacetIndex: snapshotFacetIndex,
            vocabulary: snapshotVocab,
            nutrientRankings: snapshotRankings,
            quickAgeMonths: nil,
            forcePhDisplay: false,
            isFavoritesOnly: false,
            isRecipesOnly: searchMode == .recipes,
            isMenusOnly: false,
            searchMode: searchMode,
            profileConstraints: nil,
            excludedFoodIDs: [],
            ayurvedaFilters: .empty,
            temporalContext: AyurvedaSearchTemporalContext.current(),
            constitutionTarget: nil,
            phSortOrder: nil,
            container: self.container
        )

        // Map IDs to CompactFoodItems
        let safeLimit = max(0, limit)
        let limitedIDs = resultIDs.prefix(safeLimit)
        
        return limitedIDs.compactMap { snapshotMap[$0] }
    }
}

extension SmartFoodSearch3 {
    
    /// Специализиран метод за AI генераторите.
    /// Изпълнява търсене, но връща `PersistentIdentifier` и прилага допълнително филтриране
    /// по задължителни ключови думи (headwords), за да се избегнат халюцинации (напр. "Chicken Seasoning" вместо "Chicken").
    @MainActor
    func searchFoodsAI(
        query: String,
        limit: Int = 50,
        context: String? = nil, // Context параметърът може да се ползва за re-ranking в бъдеще, засега го пазим за съвместимост
        requiredHeadwords: [String]? = nil
    ) async -> [PersistentIdentifier] {
        
        // 1. Извикваме стандартната търсачка, но искаме повече резултати, за да имаме какво да филтрираме
        let rawResults = await searchResults(
            query: query,
            activeFilters: [],
            searchMode: nil, // Търсим във всички категории (храни и рецепти)
            limit: limit * 3 // Взимаме буфер, защото headwords филтърът може да изреже много
        )
        
        var candidates = rawResults
        
        // 2. Прилагаме филтър за задължителни думи (Headwords Strict Guard)
        if let heads = requiredHeadwords, !heads.isEmpty {
            let lowerHeads = heads.map { $0.lowercased() }
            
            candidates = candidates.filter { item in
                let lowerName = item.name.lowercased()
                let itemTokens = Set(item.searchTokens.map { $0.lowercased() })
                
                // Проверяваме дали името съдържа поне един от задължителните headwords
                // Търсим както като подниз, така и като точен токен за по-голяма сигурност
                return lowerHeads.contains { head in
                    lowerName.contains(head) || itemTokens.contains(head)
                }
            }
        }
        
        // 3. Връщаме само идентификаторите до лимита
        return candidates.prefix(limit).map { $0.persistentModelID }
    }
}



extension SmartFoodSearch3 {
    nonisolated static func normalizedNumericValue(
        _ value: Double,
        unitString: String?,
        for nutrient: NutrientType
    ) -> Double {
        // Canonical unit for this nutrient (per 100 g in the DB)
        let defaultUnitRaw = SearchKnowledgeBase.shared.defaultUnit(for: nutrient)
        let defaultUnit = defaultUnitRaw
            .filter { $0.isLetter || $0 == "µ" }
            .lowercased()

        enum CanonicalKind {
            case energyKcal
            case energyKj
            case grams
            case milligrams
            case micrograms
            case other
        }

        let canonical: CanonicalKind
        switch defaultUnit {
        case "kj":
            canonical = .energyKj
        case "kcal", "cal", "calorie", "calories":
            canonical = .energyKcal
        case "kg", "gram", "grams", "g":
            canonical = .grams
        case "mg", "milligram", "milligrams":
            canonical = .milligrams
        case "µg", "ug", "mcg", "microgram", "micrograms":
            canonical = .micrograms
        default:
            canonical = .other
        }

        var inputUnit = unitString?
            .filter { $0.isLetter || $0 == "µ" }
            .lowercased() ?? ""

        if inputUnit.isEmpty {
            inputUnit = defaultUnit
        }

        switch canonical {
        case .energyKcal:
            switch inputUnit {
            case "kj":
                return value / 4.184
            default:
                return value
            }

        case .energyKj:
            switch inputUnit {
            case "kcal", "cal", "calorie", "calories":
                return value * 4.184
            default:
                return value
            }

        case .grams, .milligrams, .micrograms:
            // First convert input to grams
            var grams: Double
            switch inputUnit {
            case "kg", "kilogram", "kilograms":
                grams = value * 1000.0
            case "g", "gram", "grams":
                grams = value
            case "mg", "milligram", "milligrams":
                grams = value / 1000.0
            case "µg", "ug", "mcg", "microgram", "micrograms":
                grams = value / 1_000_000.0
            case "ng":
                grams = value / 1_000_000_000.0
            default:
                grams = value
            }

            switch canonical {
            case .grams:
                return grams
            case .milligrams:
                return grams * 1000.0
            case .micrograms:
                return grams * 1_000_000.0
            default:
                return value
            }

        case .other:
            // For dimensionless / percent-type nutrients, just return the raw value
            return value
        }
    }
    
    func refreshData() {
        let store = SearchIndexStore.shared
        guard loadedIndexRevision != store.revision else { return }
        print(
            "🔄 [SmartSearch] Refreshing internal cache "
                + "(revision: \(loadedIndexRevision) → \(store.revision))"
        )
        applyLoadedIndex()
    }
}
