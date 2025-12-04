import Foundation
import Combine
@preconcurrency import NaturalLanguage
import SwiftData

// Global embedding instance reused for semantic neighbors
private let smartFoodSearchEmbedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

fileprivate struct ProfileSearchConstraints: Sendable {
    let ageInMonths: Int
    let requiredDiets: Set<String>    // Диети, които профилът има (храната трябва да ги спазва)
    let avoidedAllergens: Set<String> // Алергени, които профилът има (храната не трябва да ги съдържа)
}

@MainActor
class SmartFoodSearch3: ObservableObject {
    
    // MARK: - Public Enums
    public enum SearchMode: String, CaseIterable, Identifiable, Sendable {
        case nutrients = "Nutrients"
        case recipes = "Recipes"
        case menus = "Menus"
        case diets = "Diets"
        case mealPlans = "Meal Plans"
        
        public var id: String { rawValue }
    }
    
    // MARK: - Outputs (for UI)
    
    @Published var displayedResults: [FoodItem] = []
    @Published var isLoading: Bool = false
    @Published var searchContext: SearchContext = SearchContext()
    
    // MARK: - Internal Data (Lightweight Index)
    
    private var allFoods: [CompactFoodItem] = []
    
    /// token -> set of CompactFoodItem IDs
    private var invertedIndex: [String: Set<Int>] = [:]
    
    /// id -> CompactFoodItem
    private var compactMap: [Int: CompactFoodItem] = [:]
    
    private var vocabulary: [String] = []
    private var maxNutrientValues: [NutrientType: Double] = [:]
    private var cachedKnownDiets: Set<String> = []
    
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
            phSortOrder: PhSortOrder? = nil // ✅ НОВ ПАРАМЕТЪР
        ) {
            let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)
            
            print("\n=============================================================")
            print("🔍 [SmartSearch] STARTING SEARCH: '\(rawQuery)' | Mode: \(searchMode?.rawValue ?? "None") | pH Order: \(String(describing: phSortOrder))")
            print("=============================================================\n")
            
            var profileConstraints: ProfileSearchConstraints? = nil
            if let p = profile {
                profileConstraints = ProfileSearchConstraints(
                    ageInMonths: p.ageInMonths,
                    requiredDiets: Set(p.diets.map { $0.name }),
                    avoidedAllergens: Set(p.allergens.map { $0.rawValue })
                )
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
                lastPhSortOrder = phSortOrder // ✅ Обновяване на state
                
                searchTask?.cancel()
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
            lastPhSortOrder = phSortOrder // ✅ Обновяване на state
            
            // Snapshot lightweight state
            let snapshotAllFoods = allFoods
            let snapshotMap = compactMap
            let snapshotIndex = invertedIndex
            let snapshotVocab = vocabulary
            let snapshotMaxValues = maxNutrientValues
            let snapshotDietsFromDB = cachedKnownDiets
            let snapshotRankings = nutrientRankings
            let snapshotExcludedIDs = excludedFoodIDs
            
            let snapshotAvailableDiets: Set<String> = {
                var names = snapshotDietsFromDB
                for d in defaultDietsList {
                    names.insert(d.name)
                }
                return names
            }()
            
            searchTask = Task(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
                if Task.isCancelled { return }
                
                print("🚀 [SmartSearch] Task started for: '\(canonicalQuery)'")
                
                let (resultIDs, intent, _, forceShowPH) = await self.runSearchLogic(
                    query: canonicalQuery,
                    activeFilters: activeFilters,
                    compactMap: snapshotMap,
                    allFoods: snapshotAllFoods,
                    maxValues: snapshotMaxValues,
                    availableDiets: snapshotAvailableDiets,
                    invertedIndex: snapshotIndex,
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
                    phSortOrder: phSortOrder, // ✅ Подаваме надолу
                    container: self.container
                )
                
                if Task.isCancelled {
                    print("🛑 [SmartSearch] Task cancelled before UI update.")
                    return
                }
                
                await MainActor.run {
                    print("✅ [SmartSearch] Updating UI on MainActor. Found IDs: \(resultIDs.count)")
                    
                    self.fullResultIDs = resultIDs
                    self.updateContext(intent: intent,
                                       activeFilters: activeFilters,
                                       forceShowPH: forceShowPH)
                    
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
        guard referenceWeight > 0 else { return nil }
        
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
    }
    
    private func updateContext(intent: SearchIntent,
                               activeFilters: Set<NutrientType>,
                               forceShowPH: Bool) {
        var display = intent.nutrientGoals.map { $0.nutrient }
        for f in activeFilters where !display.contains(f) {
            display.append(f)
        }
        var seen = Set<NutrientType>()
        let uniqueDisplay = display.filter { seen.insert($0).inserted }
        var ageStr: String? = nil
        if let age = intent.targetConsumerAge {
            ageStr = age >= 12 ? "\(Int(age / 12))y+" : "\(Int(age))m+"
        }
        searchContext = SearchContext(
            displayNutrients: uniqueDisplay,
            activeDiet: intent.dietFilter,    // 👈 важно – dietFilter от SearchIntent
            activeConstraint: nil,
            activeAgeLimit: ageStr,
            isPhActive: forceShowPH || intent.phConstraint != nil
        )
    }
    
        // MARK: - Core Logic
            
        nonisolated private func runSearchLogic(
            query: String,
            activeFilters: Set<NutrientType>,
            compactMap: [Int: CompactFoodItem],
            allFoods: [CompactFoodItem],
            maxValues: [NutrientType: Double],
            availableDiets: Set<String>,
            invertedIndex: [String: Set<Int>],
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
            phSortOrder: PhSortOrder?, // ✅ НОВ ПАРАМЕТЪР
            container: ModelContainer
        ) async -> (resultIDs: [Int], intent: SearchIntent, effectiveTokens: [String], forceShowPH: Bool) {
            
            let simpleRawQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            let hasNonLatinLetters: Bool = simpleRawQuery.unicodeScalars.contains { scalar in
                if scalar.isASCII { return false }
                if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
                if CharacterSet.punctuationCharacters.contains(scalar) { return false }
                return true
            }
            
            let rawPhCount: Int = {
                let parts = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                return parts.filter { $0 == "ph" }.count
            }()
            
            let parsed = await Tokenizer.parse(query, availableDiets: availableDiets)
            let hasDigits = query.rangeOfCharacter(from: .decimalDigits) != nil
            var textTokens = parsed.textTokens
            let simplePHToggle = (rawPhCount >= 1 && !hasDigits)
            
            if simplePHToggle {
                textTokens = textTokens.filter { $0.caseInsensitiveCompare("ph") != .orderedSame }
            }
            
            let combinedAge = quickAgeMonths ?? parsed.targetConsumerAge
            let forceShowPH = simplePHToggle || (rawPhCount >= 2 && parsed.phConstraint == nil) || forcePhDisplay
            
            // --- ПРИОРИТЕТИ ---
            var mergedGoals: [NutrientGoal] = []
            
            // 1. Филтри от UI
            for filter in activeFilters {
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
            let lowerQuery = query.lowercased()
            let shouldUseConstraintEngine: Bool = {
                if lowerQuery.rangeOfCharacter(from: .decimalDigits) != nil { return true }
                if lowerQuery.contains("ph") || lowerQuery.contains("acid") || lowerQuery.contains("alkaline") { return true }
                if lowerQuery.contains("free") || lowerQuery.contains("without") || lowerQuery.contains("no ") { return true }
                if lowerQuery.contains("less than") || lowerQuery.contains("more than") ||
                    lowerQuery.contains("at least") || lowerQuery.contains("at most") ||
                    lowerQuery.contains("between") || lowerQuery.contains("from ") { return true }
                if lowerQuery.contains("low ") || lowerQuery.contains("high ") || lowerQuery.contains("rich ") || lowerQuery.contains("poor ") { return true }
                return false
            }()
            
            if shouldUseConstraintEngine {
                print("🧮 [Constraints] Using constraint engine for query: \(query)")
                mappedConstraints = await MainActor.run {
                    let rawConstraints = ConstraintExtractor.extract(from: query)
                    return ConstraintMapper.map(rawConstraints)
                }
            } else {
                mappedConstraints = ConstraintMapperResult()
            }
            
            var numericGoals = mappedConstraints.nutrientGoals
            let fallbackGoals = SmartFoodSearch3.parseNumericNutrientConstraintsFromQuery(query)
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
            
            // --- Diets ---
            let baseExcludedDiets = parsed.excludedDiets.union(
                Self.deriveExcludedDiets(negativeTokens: parsed.negativeTokens, availableDiets: availableDiets)
            )
            let excludedDietNames = baseExcludedDiets.union(mappedConstraints.excludeDiets)
            let combinedDiets = parsed.diets.union(mappedConstraints.includeDiets)
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
                explicitPhConstraint = .range(6.5, 7.5) // ✅ НОВО: Връща само храни с pH между 6.5 и 7.5
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
                    diets: combinedDiets,
                    dietFilter: parsed.dietFilter,
                    excludedDiets: excludedDietNames,
                    targetConsumerAge: combinedAge,
                    allergenExclusions: combinedAllergenExclusions,
                    excludeAllAllergens: parsed.excludeAllAllergens,
                    phConstraint: phConstraintForIntent
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
            let ingredientKeys = Set(SearchKnowledgeBase.shared.ingredientToDietMap.keys)

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
                    
                    // FIX: If the word is a known ingredient (even if it links to a diet),
                    // treat it as a STRICT text token, not a skippable command.
                    let isIngredient = SearchKnowledgeBase.shared.ingredientToDietMap.keys.contains(lower)
                    
                    // If it's an ingredient, force false. Otherwise respect rawIsPrefix.
                    let effectiveIsPrefix = isIngredient ? false : rawIsPrefix
                    
                    // "ph" and "no" remain special 2-char commands
                    let isCommand: Bool = (t.count <= 2) ? (lower == "ph" || lower == "no") : effectiveIsPrefix
                    
                    map[t] = isCommand
                }
                return map
            }
            
            var candidateIDs: Set<Int>? = nil
            var effectiveTextTokens: [String] = []
            let trimmedNumericQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
            
            if Task.isCancelled { return ([], makeIntent(), [], forceShowPH) }
            
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
            
            for (index, item) in sequence.enumerated() {
                if hasNonLatinLetters && (simpleRawQuery.isEmpty || !item.lowercasedName.contains(simpleRawQuery)) { continue }
                if index % 500 == 0 && Task.isCancelled { return ([], intent, [], forceShowPH) }
                if excludedFoodIDs.contains(item.id) { continue }
                
                if let mode = searchMode {
                    switch mode {
                    case .recipes: if item.isRecipe || item.isMenu { continue }
                    case .menus: if item.isMenu { continue }
                    case .nutrients, .mealPlans:
                        if let cons = profileConstraints {
                            if Double(item.minAgeMonths) > Double(cons.ageInMonths) { continue }
                            if !cons.requiredDiets.isEmpty {
                                var meetsAll = true
                                for d in cons.requiredDiets { if !item.fits(dietName: d) { meetsAll = false; break } }
                                if !meetsAll { continue }
                            }
                            if !cons.avoidedAllergens.isEmpty {
                                var hasAllergen = false
                                for a in cons.avoidedAllergens { if item.contains(allergen: a) { hasAllergen = true; break } }
                                if hasAllergen { continue }
                            }
                        }
                    case .diets: break
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

                if !intent.excludedDiets.isEmpty {
                    var hasExcludedDiet = false
                    for excluded in intent.excludedDiets where item.fits(dietName: excluded) { hasExcludedDiet = true; break }
                    if hasExcludedDiet { continue }
                }
                if !intent.diets.isEmpty {
                    var meetsAll = true
                    for d in intent.diets where !item.fits(dietName: d) { meetsAll = false; break }
                    if !meetsAll { continue }
                }
                if let uiDiet = intent.dietFilter, !item.fits(dietName: uiDiet.rawValue) { continue }
                if let age = intent.targetConsumerAge, Double(item.minAgeMonths) > age { continue }
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
                    if item.ph == 0.0 { continue }
                    var passesPh = true
                    switch phLimit {
                    case .min(let v):       if item.ph < v { passesPh = false }
                    case .max(let v):       if item.ph > v { passesPh = false }
                    case .strictMin(let v): if item.ph <= v { passesPh = false }
                    case .strictMax(let v): if item.ph >= v { passesPh = false }
                    case .range(let l, let h): if item.ph < l || item.ph > h { passesPh = false }
                    case .notEqual(let v):  if abs(item.ph - v) < 0.1 { passesPh = false }
                    case .high:             if item.ph < 7.0 { passesPh = false }
                    case .low:              if item.ph > 7.0 { passesPh = false }
                        
                    // ✅ ПРОМЯНА: Новите кейсове не филтрират нищо, само позволяват сортиране по-долу
                    case .lowest, .highest:
                        break
                    }
                    if !passesPh { continue }
                }
                
                var passesNutrients = true
                for goal in intent.nutrientGoals {
                    let val: Double = (item.referenceWeightG > 0)
                        ? (item.value(for: goal.nutrient) / item.referenceWeightG) * 100.0
                        : 0.0

                    // 🔎 Трактуваме 0 като "липсва данни" при ЧИСЛОВИ ограничения,
                    // за да не минават храни с 0 витамин C при "vitamin c < 2mcg".
                    let isNumericConstraint: Bool
                    switch goal.constraint {
                    case .min, .max, .strictMin, .strictMax, .range, .notEqual:
                        isNumericConstraint = true
                    case .high, .low, .lowest, .highest: // Добавяме новите кейсове и тук за пълнота, макар че не се използват за нутриенти
                        isNumericConstraint = false
                    }

                    if isNumericConstraint && val == 0 {
                        passesNutrients = false
                        print("🧪 [SmartSearch] Excluding '\(item.lowercasedName)' for \(goal.nutrient) – numeric constraint \(goal.constraint) but value is exactly 0")
                        break
                    }

                    switch goal.constraint {
                    case .min(let v):       if val < v { passesNutrients = false }
                    case .max(let v):       if val > v { passesNutrients = false }
                    case .strictMin(let v): if val <= v { passesNutrients = false }
                    case .strictMax(let v): if val >= v { passesNutrients = false }
                    case .range(let l, let h): if val < l || val > h { passesNutrients = false }
                    case .notEqual(let v):  if abs(val - v) < 0.01 { passesNutrients = false }
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
            let rawWords = query.lowercased().components(separatedBy: allowedChars.inverted).filter { !$0.isEmpty }
            let validRawWords: [String] = rawWords.filter { raw in effectiveTextTokens.contains(Tokenizer.processWord(raw)) }
            let rawCleanQuery = validRawWords.joined(separator: " ")
            let rawPaddedQuery = " " + rawCleanQuery + " "
            var rankedItems: [(item: CompactFoodItem, score: Double)] = []
            
            for (index, item) in itemsToRank.enumerated() {
                if index % 500 == 0 && Task.isCancelled { return ([], intent, [], forceShowPH) }
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
                rankedItems.append((item, score))
            }
            
            let finalResults: [Int]
            if let phLimit = intent.phConstraint {
                // Тук се случва сортирането по pH!
                let preferLowPH: Bool = {
                    switch phLimit {
                    // ✅ ПРОМЯНА: Добавяме .lowest тук (възходящо сортиране: 1 -> 14)
                    case .max, .strictMax, .low, .lowest: return true
                    // .highest отива в default (false), което значи низходящо (14 -> 1)
                    default: return false
                    }
                }()
                let primaryGoal = intent.nutrientGoals.first
                finalResults = rankedItems.sorted { lhs, rhs in
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
                finalResults = rankedItems.sorted { lhs, rhs in
                    let leftVal = lhs.item.value(for: primaryGoal.nutrient); let rightVal = rhs.item.value(for: primaryGoal.nutrient)
                    if leftVal != rightVal { return preferLowValues ? (leftVal < rightVal) : (leftVal > rightVal) }
                    if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                    return lhs.item.lowercasedName < rhs.item.lowercasedName
                }.map { $0.item.id }
            } else {
                finalResults = rankedItems.sorted { lhs, rhs in
                    if abs(lhs.score - rhs.score) > 0.001 { return lhs.score > rhs.score }
                    return lhs.item.lowercasedName < rhs.item.lowercasedName
                }.map { $0.item.id }
            }
            
            return (finalResults, intent, effectiveTextTokens, forceShowPH)
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
            // 1. Ако локалният инстанс вече има данни - не правим нищо
            if !allFoods.isEmpty {
                if lastCanonicalQuery.isEmpty,
                   lastActiveFilters.isEmpty,
                   displayedResults.isEmpty {
                    showDefaultResultsIfPossible()
                }
                return
            }
            
            // 2. ⚡️ FAST PATH: Проверка дали Singleton Store вече има данни в паметта
            // Тъй като и двете са @MainActor, можем да четем директно без await.
            let store = SearchIndexStore.shared
            if !store.compactFoods.isEmpty {
                // Копираме референциите веднага (синхронно)
                self.allFoods = store.compactFoods
                self.compactMap = store.compactMap
                self.invertedIndex = store.invertedIndex
                self.vocabulary = store.vocabulary
                self.maxNutrientValues = store.maxNutrientValues
                self.cachedKnownDiets = store.knownDiets
                self.nutrientRankings = store.nutrientRankings
                
                // Данните са готови веднага.
                // Ако няма активно търсене, показваме дефолтните резултати.
                if self.lastCanonicalQuery.isEmpty, self.lastActiveFilters.isEmpty {
                    self.showDefaultResultsIfPossible()
                }
                return
            }

            // 3. SLOW PATH: Ако Store е празен, зареждаме асинхронно от базата
            isLoading = true
            Task {
                await SearchIndexStore.shared.ensureLoaded(container: container)
                await MainActor.run {
                    let store = SearchIndexStore.shared
                    self.allFoods = store.compactFoods
                    self.compactMap = store.compactMap
                    self.invertedIndex = store.invertedIndex
                    self.vocabulary = store.vocabulary
                    self.maxNutrientValues = store.maxNutrientValues
                    self.cachedKnownDiets = store.knownDiets
                    self.nutrientRankings = store.nutrientRankings
                    self.isLoading = false
                    
                    if self.lastCanonicalQuery.isEmpty, self.lastActiveFilters.isEmpty {
                        self.showDefaultResultsIfPossible()
                    }
                }
            }
        }
    
    // MARK: - Diet Derivation
    
    nonisolated private static func deriveExcludedDiets(negativeTokens: Set<String>, availableDiets: Set<String>) -> Set<String> {
        guard !negativeTokens.isEmpty else { return [] }
        var result = Set<String>()
        let lowerToDietName: [String: String] = availableDiets.reduce(into: [:]) { $0[$1.lowercased()] = $1 }
        for token in negativeTokens {
            let lower = token.lowercased()
            if let dietType = SearchKnowledgeBase.shared.dietMap[lower] { result.insert(dietType.rawValue); continue }
            if let mappedName = SearchKnowledgeBase.shared.dietSynonyms[lower] { result.insert(mappedName); continue }
            if let exact = lowerToDietName[lower] { result.insert(exact); continue }
            if let (_, name) = lowerToDietName.first(where: { $0.key.contains(lower) }) { result.insert(name) }
        }
        return result
    }
    
    // MARK: - Numeric Constraint Parsing (regex engine)
    
    nonisolated private static func parseNumericNutrientConstraints(from query: String) -> [NutrientGoal] {
        var lower = query.lowercased()
        
        // REPLACEMENT LOGIC:
        let regexReplacements: [(String, String)] = [
            // 1. Longest phrases
            (#"\bless\s+than\s+or\s+equal\s+to\b"#, " <= "),
            (#"\bno\s+more\s+than\b"#, " <= "),
            (#"\bat\s+most\b"#, " <= "),
            (#"\bmaximum\b"#, " <= "),
            (#"\bgreater\s+than\s+or\s+equal\s+to\b"#, " >= "),
            (#"\bat\s+least\b"#, " >= "),
            (#"\bminimum\b"#, " >= "),
            
            // 2. Standard phrases
            (#"\bless\s+than\b"#, " <= "),
            (#"\bfewer\s+than\b"#, " <= "),
            (#"\blower\s+than\b"#, " <= "),
            (#"\bmore\s+than\b"#, " >= "),
            (#"\bgreater\s+than\b"#, " >= "),
            (#"\bhigher\s+than\b"#, " >= "),
            
            // 3. Short colloquialisms
            (#"\bunder\b"#, " <= "),
            (#"\bbelow\b"#, " <= "),
            (#"\bless\b"#, " <= "),
            (#"\bfewer\b"#, " <= "),
            (#"\blower\b"#, " <= "),
            (#"\bmin\b"#, " >= "),
            (#"\bmax\b"#, " <= "),
            (#"\bover\b"#, " >= "),
            (#"\babove\b"#, " >= "),
            (#"\bexceeds\b"#, " >= "),
            (#"\bmore\b"#, " >= "),
            (#"\bgreater\b"#, " >= "),
            (#"\bhigher\b"#, " >= ")
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
            if trimmedName.contains("ph") { return false }
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
    
    // MARK: - Unit Normalisation
    
    nonisolated private static func normalizedNumericValue(
        _ value: Double,
        unitString: String?,
        for nutrient: NutrientType
    ) -> Double {
        // Decide canonical unit based on your data model (default unit for this nutrient)
        let defaultUnitRaw = SearchKnowledgeBase.shared.defaultUnit(for: nutrient)
        let defaultUnit = defaultUnitRaw.filter { $0.isLetter || $0 == "µ" }.lowercased()
        
        // Classify canonical target
        enum CanonicalMassUnit {
            case grams, milligrams, micrograms
        }
        
        let isEnergy: Bool
        let canonicalMass: CanonicalMassUnit?
        
        switch defaultUnit {
        case "kcal", "cal", "calorie", "calories", "kj":
            isEnergy = true
            canonicalMass = nil
        case "kg", "g", "gram", "grams":
            isEnergy = false
            canonicalMass = .grams
        case "µg", "mcg", "ug", "microgram", "micrograms", "ng":
            isEnergy = false
            canonicalMass = .micrograms
        case "mg", "milligram", "milligrams":
            fallthrough
        default:
            isEnergy = false
            canonicalMass = .milligrams
        }
        
        print("⚖️ [UnitCheck] Converting \(value) \(unitString ?? "n/a") for \(nutrient)")
        print("⚖️ [UnitCheck] Default data unit for \(nutrient): '\(defaultUnitRaw)' (canonical: \(canonicalMass.map { "\($0)" } ?? (isEnergy ? "energy" : "unknown")))")
        
        // Normalize incoming unit text
        var inputUnit = ""
        if let us = unitString {
            inputUnit = us.filter { $0.isLetter || $0 == "µ" }.lowercased()
        }
        
        // If no unit was provided in the query, assume the default data unit
        if inputUnit.isEmpty {
            inputUnit = defaultUnit
            print("⚖️ [UnitCheck] No unit provided, assuming default data unit '\(inputUnit)' for \(nutrient)")
        }
        
        // Handle energy separately
        if isEnergy {
            var energyKcal: Double?
            switch inputUnit {
            case "kcal", "cal", "calorie", "calories":
                energyKcal = value
            case "kj":
                energyKcal = value / 4.184
            default:
                // If someone typed mg/g etc. for energy, treat the number as already kcal
                energyKcal = value
                print("⚖️ [UnitCheck] Unexpected mass unit '\(inputUnit)' for energy; treating \(value) as kcal")
            }
            let result = energyKcal ?? value
            print("🔍 [SmartSearch] Normalizing \(value) [\(inputUnit)] for \(nutrient.rawValue) -> Result: \(result) (kcal)")
            return result
        }
        
        // Convert any mass-like unit to grams first
        var grams: Double
        switch inputUnit {
        case "kg", "kilogram", "kilograms":
            grams = value * 1000.0
            print("⚖️ [UnitCheck] Step 1: \(value) kg -> \(grams) grams")
        case "g", "gram", "grams":
            grams = value
            print("⚖️ [UnitCheck] Step 1: \(value) g -> \(grams) grams")
        case "mg", "milligram", "milligrams":
            grams = value / 1000.0
            print("⚖️ [UnitCheck] Step 1: \(value) mg -> \(grams) grams")
        case "µg", "mcg", "ug", "microgram", "micrograms":
            grams = value / 1_000_000.0
            print("⚖️ [UnitCheck] Step 1: \(value) µg -> \(grams) grams")
        case "ng":
            grams = value / 1_000_000_000.0
            print("⚖️ [UnitCheck] Step 1: \(value) ng -> \(grams) grams")
        default:
            grams = value
            print("⚖️ [UnitCheck] Step 1: Unknown unit '\(inputUnit)', assuming grams/raw: \(grams)")
        }
        
        // Now convert from grams to the canonical mass unit
        let result: Double
        switch canonicalMass ?? .milligrams {
        case .grams:
            result = grams
        case .milligrams:
            result = grams * 1000.0
            print("⚖️ [UnitCheck] Step 2: \(grams) grams -> \(result) mg")
        case .micrograms:
            result = grams * 1_000_000.0
            print("⚖️ [UnitCheck] Step 2: \(grams) grams -> \(result) µg")
        }
        
        print("🔍 [SmartSearch] Normalizing \(value) [\(inputUnit)] for \(nutrient.rawValue) -> Result: \(result)")
        return result
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
        phSortOrder: PhSortOrder? = nil,
        limit: Int = 20
    ) async -> [FoodItem] {
        // Make sure index is loaded (this may populate allFoods / invertedIndex / etc.)
        if allFoods.isEmpty {
            await loadData()
        }

        let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)

        // Build profile constraints just like in performSearch(...)
        var profileConstraints: ProfileSearchConstraints? = nil
        if let p = profile {
            profileConstraints = ProfileSearchConstraints(
                ageInMonths: p.ageInMonths,
                requiredDiets: Set(p.diets.map { $0.name }),
                avoidedAllergens: Set(p.allergens.map { $0.rawValue })
            )
        }

        // Snapshot lightweight state (same pattern as performSearch)
        let snapshotAllFoods = allFoods
        let snapshotMap = compactMap
        let snapshotIndex = invertedIndex
        let snapshotVocab = vocabulary
        let snapshotMaxValues = maxNutrientValues
        let snapshotDietsFromDB = cachedKnownDiets
        let snapshotRankings = nutrientRankings
        let snapshotExcludedIDs = excludedFoodIDs

        let snapshotAvailableDiets: Set<String> = {
            var names = snapshotDietsFromDB
            for d in defaultDietsList {
                names.insert(d.name)
            }
            return names
        }()

        // Run the full search logic pipeline (constraints, nutrients, pH, diets, scoring, sorting, etc.)
        let (resultIDs, _, _, _) = await self.runSearchLogic(
            query: canonicalQuery,
            activeFilters: activeFilters,
            compactMap: snapshotMap,
            allFoods: snapshotAllFoods,
            maxValues: snapshotMaxValues,
            availableDiets: snapshotAvailableDiets,
            invertedIndex: snapshotIndex,
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
            await loadData()
        }

        let canonicalQuery = SmartFoodSearch3.canonicalQuery(from: rawQuery)

        // Snapshot lightweight state
        let snapshotAllFoods = allFoods
        let snapshotMap = compactMap
        let snapshotIndex = invertedIndex
        let snapshotVocab = vocabulary
        let snapshotMaxValues = maxNutrientValues
        let snapshotRankings = nutrientRankings
        
        let snapshotAvailableDiets: Set<String> = {
            var names = cachedKnownDiets
            for d in defaultDietsList {
                names.insert(d.name)
            }
            return names
        }()

        // Run search logic
        let (resultIDs, _, _, _) = await self.runSearchLogic(
            query: canonicalQuery,
            activeFilters: [],
            compactMap: snapshotMap,
            allFoods: snapshotAllFoods,
            maxValues: snapshotMaxValues,
            availableDiets: snapshotAvailableDiets,
            invertedIndex: snapshotIndex,
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
