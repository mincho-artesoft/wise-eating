//import Combine
//import Foundation
//import SwiftData
//
//@MainActor
//final class FoodSearchVM: ObservableObject {
//    
//    // MARK: - Public toggles (recipes / menus) with mutual exclusion
//    @Published var showRecipesOnly: Bool = false {
//        didSet {
//            guard !isAdjustingTypeFilter else { return }
//            if showRecipesOnly && showMenusOnly {
//                isAdjustingTypeFilter = true
//                showMenusOnly = false
//                isAdjustingTypeFilter = false
//            }
//            resetAndLoad()
//        }
//    }
//    
//    @Published var showMenusOnly: Bool = false {
//        didSet {
//            guard !isAdjustingTypeFilter else { return }
//            if showMenusOnly && showRecipesOnly {
//                isAdjustingTypeFilter = true
//                showRecipesOnly = false
//                isAdjustingTypeFilter = false
//            }
//            resetAndLoad()
//        }
//    }
//    
//    private var isAdjustingTypeFilter = false
//    
//    enum SearchContext { case none, recipeEditor, menuEditor }
//    
//    @Published var searchContext: SearchContext = .none {
//        didSet { if oldValue != searchContext { resetAndLoad() } }
//    }
//    
//    // MARK: - Public Input / Output
//    @Published var query: String = ""
//    @Published var vitaminFilters: Set<String> = []
//    @Published var mineralFilters: Set<String> = []
//    
//    /// Ако е зададено, филтрира резултатите, за да покаже само храни, подходящи за дадена възраст.
//    @Published var profileAgeInMonths: Int? = nil {
//        didSet {
//            if oldValue != profileAgeInMonths {
//                resetAndLoad()
//            }
//        }
//    }
//    
//    // Диетични и алергенни филтри – използват се само ако НЕ са празни
//    @Published var dietFilters: Set<Diet> = []
//    @Published var allergenFilters: Set<Allergen> = []
//    
//    @Published private(set) var items: [FoodItem] = []
//    @Published private(set) var hasMore: Bool = false
//    
//    @Published private(set) var favoriteItems: [FoodItem] = []
//    @Published var isFavoritesModeActive: Bool = false {
//        didSet { resetAndLoad() }
//    }
//    @Published var selectedNutrientID: String? = nil
//    
//    /// Показвай само потребителски добавени храни (за overlay търсене при default диета)
//    @Published var onlyUserAdded: Bool = false {
//        didSet { resetAndLoad() }
//    }
//    
//    // Loading & timing
//    @Published private(set) var isLoading: Bool = false
//    private var timingLabel: String?
//    private var timingStart: CFAbsoluteTime?
//    
//    // MARK: - Private State
//    private weak var ctx: ModelContext?
//    private var container: ModelContainer?
//    private var cancellables = Set<AnyCancellable>()
//    
//    private let pageSize = 50
//    
//    // Text search offsets
//    private var startsOffset = 0
//    private var containsOffset = 0
//    
//    private var currentTask: Task<Void, Never>?
//    private var excludedIDs = Set<FoodItem.ID>()
//    
//    // Nutrient paging
//    private let nutrientPage = 60
//    private var nutrientOffset = 0
//    
//    // --- NEW: concurrency guard against duplicate appends ---
//    private var generation: Int = 0
//    
//    @inline(__always)
//    private func bumpGeneration() { generation &+= 1 }
//    
//    @inline(__always)
//    private func appendUniquePreservingOrder(_ incoming: [FoodItem], order: [Int : Int]) {
//        let existing = Set(items.map(\.id))
//        var toAppend = incoming.filter { !existing.contains($0.id) }
//        toAppend.sort { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
//        items.append(contentsOf: toAppend)
//    }
//    
//    // MARK: - Init
//    init() {
//        Publishers.CombineLatest4(
//            $query.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.removeDuplicates(),
//            $vitaminFilters.removeDuplicates(),
//            $mineralFilters.removeDuplicates(),
//            $selectedNutrientID.removeDuplicates()
//        )
//        .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
//        .sink { [weak self] _ in self?.resetAndLoad() }
//        .store(in: &cancellables)
//        
//        // Промяна на diet/allergen филтрите също презарежда, но се прилагат само ако са непразни
//        $dietFilters
//            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
//            .sink { [weak self] _ in self?.resetAndLoad() }
//            .store(in: &cancellables)
//        
//        $allergenFilters
//            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
//            .sink { [weak self] _ in self?.resetAndLoad() }
//            .store(in: &cancellables)
//    }
//    
//    // MARK: - External Helpers
//    
//    /// Attaches the real `ModelContext` (called from the View).
//    func attach(context: ModelContext) {
//        guard ctx !== context else { return }
//        ctx = context
//        container = context.container
//        // Няма resetAndLoad() тук — View-то (или други setters) стартират първоначалното зареждане.
//    }
//    
//    func exclude(_ foods: Set<FoodItem>) {
//        let newIDs = Set(foods.map(\.id))
//        guard newIDs != excludedIDs else { return }
//        excludedIDs = newIDs
//        resetAndLoad()
//    }
//    
//    // --- НАЧАЛО НА ПРОМЯНАТА ---
//    /// Public метод за безопасно обновяване на `items` отвън.
//    func setItems(to newItems: [FoodItem]) {
//        self.items = newItems
//    }
//    // --- КРАЙ НА ПРОМЯНАТА ---
//    
//    func loadNextPage() {
//        guard !isLoading, hasMore, !isFavoritesModeActive else { return }
//        if selectedNutrientID != nil {
//            loadMoreNutrientPage()
//        } else {
//            loadTextPage()
//        }
//    }
//    
//    /// Връща стойността и мерната единица на избрания нутриент за даден FoodItem, **нормализирано към 100 грама**.
//    /// Работи коректно за обикновени храни, рецепти и менюта.
//    func nutrientInfo(for item: FoodItem) -> (value: Double, unit: String)? {
//        guard let id = selectedNutrientID else { return nil }
//        
//        // Помощна функция за конвертиране на мерни единици за по-добър изглед.
//        let convert = { (raw: Double, unit: String) -> (Double, String) in
//            switch unit.lowercased() {
//            case "mg" where raw < 1:       return (raw * 1_000, "µg")
//            case "mg" where raw >= 1_000:  return (raw / 1_000, "g")
//            default: return (raw, unit)
//            }
//        }
//        
//        // 1) ОБЩАТА стойност на нутриента за ОБЩОТО тегло на продукта.
//        guard let (totalValue, unit) = item.value(of: id), totalValue > 0 else {
//            return nil
//        }
//        
//        // 2) ОБЩОТО тегло на продукта в грамове (referenceWeightG работи и за рецепти).
//        let referenceWeight = item.referenceWeightG
//        guard referenceWeight > 0 else { return nil }
//        
//        // 3) Нормализация към 100 g.
//        let valuePer100g = (totalValue / referenceWeight) * 100.0
//        
//        // 4) Форматиране за по-добър изглед.
//        return convert(valuePer100g, unit)
//    }
//    
//    // MARK: - Flow
//    private func cancelInFlight() {
//        currentTask?.cancel()
//        currentTask = nil
//    }
//    
//    private func beginTiming(_ label: String) {
//        timingLabel = label
//        timingStart = CFAbsoluteTimeGetCurrent()
//        print("[StorageSearchVM] START \(label)")
//    }
//    
//    private func endTiming() {
//        guard let label = timingLabel, let start = timingStart else { return }
//        let dt = CFAbsoluteTimeGetCurrent() - start
//        print(String(format: "[StorageSearchVM] DONE %@ in %.3f s", label, dt))
//        timingLabel = nil
//        timingStart = nil
//    }
//    
//    private func setLoading(_ flag: Bool, label: String? = nil) {
//        if flag {
//            if let label { beginTiming(label) }
//            isLoading = true
//        } else {
//            endTiming()
//            isLoading = false
//        }
//    }
//    
//    func resetAndLoad() {
//        cancelInFlight()
//        bumpGeneration()                 // <-- важна част: инвалидация на стари таскове
//        items = []
//        favoriteItems = []
//        startsOffset = 0
//        containsOffset = 0
//        nutrientOffset = 0
//        hasMore = false
//        setLoading(false)
//        load()
//    }
//    
//    private func load() {
//        guard ctx != nil else { return }
//        
//        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        if isFavoritesModeActive {
//            fetchAllFavorites(search: search)
//            return
//        }
//        
//        if selectedNutrientID != nil {
//            loadFirstNutrientPage(search: search)
//        } else {
//            // Зареждаме текстова страница дори при празен текст
//            loadTextPage()
//        }
//    }
//    
//    nonisolated private func nutrientValue(for item: FoodItem, nutrientID: String) -> Double? {
//        if nutrientID.hasPrefix("vit_") {
//            guard let vit = item.vitamins, let getter = vitaminAccess[String(nutrientID.dropFirst(4))] else { return nil }
//            return getter(vit)?.value
//        }
//        if nutrientID.hasPrefix("min_") {
//            guard let min = item.minerals, let getter = mineralAccess[String(nutrientID.dropFirst(4))] else { return nil }
//            return getter(min)?.value
//        }
//        return nil
//    }
//    
//    // MARK: - Shared helper: диета/алергени (прилага се само ако сетовете НЕ са празни)
//    private func applyDietAllergenFilters(_ foods: [FoodItem],
//                                          dietIDs: Set<String>,
//                                          allergenIDs: Set<String>) -> [FoodItem] {
//        guard !dietIDs.isEmpty || !allergenIDs.isEmpty else { return foods }
//        
//        // Разширяваме избраните алергени с подтиповете (напр. Nuts -> всички видове ядки)
//        let expandedAllergenIDs = Allergen.expandedIDs(from: allergenIDs)
//        
//        return foods.filter { item in
//            let itemDietIDs      = Set((item.diets ?? []).map(\.id))
//            let itemAllergenIDs  = Set((item.allergens ?? []).map(\.id))
//            
//            // Диетите остават "всички избрани" (AND).
//            let matchesDiets = dietIDs.isEmpty || dietIDs.allSatisfy { itemDietIDs.contains($0) }
//            
//            // Блокирай, ако храната съдържа който и да е от (разширените) забранени алергени
//            let hasNoBlockedAllergens = itemAllergenIDs.isDisjoint(with: expandedAllergenIDs)
//            
//            return matchesDiets && hasNoBlockedAllergens
//        }
//    }
//    
//    private func fetchAllFavorites(search: String) {
//        guard let container else { return }
//        setLoading(true, label: "favorites")
//        
//        let needle = search.foldedSearchKey
//        let excluded = excludedIDs
//        let context = self.searchContext
//        let capturedAge = self.profileAgeInMonths
//        let onlyUserAdded = self.onlyUserAdded
//        
//        let dietIDs     = Set(dietFilters.map(\.id))
//        let allergenIDs = Set(allergenFilters.map(\.id))
//        
//        enum TypeFilter { case all, recipes, menus }
//        let typeFilter: TypeFilter = showRecipesOnly ? .recipes : (showMenusOnly ? .menus : .all)
//        
//        let gen = self.generation   // capture generation
//        
//        cancelInFlight()
//        currentTask = Task.detached { [weak self] in
//            guard let self = self else { return }
//            
//            let capturedNutrientID = await self.selectedNutrientID
//            
//            let bg = ModelContext(container)
//            bg.autosaveEnabled = false
//            
//            func alwaysFalse() -> Predicate<FoodItem> { #Predicate { _ in false } }
//            
//            let predicate: Predicate<FoodItem>
//            switch (context, typeFilter) {
//            case (.none, .all):
//                predicate = #Predicate { item in
//                    item.isFavorite == true &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            case (.none, .recipes):
//                predicate = #Predicate { item in
//                    item.isFavorite == true && item.isRecipe == true &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            case (.none, .menus):
//                predicate = #Predicate { item in
//                    item.isFavorite == true && item.isMenu == true &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            case (.recipeEditor, .recipes), (.recipeEditor, .menus):
//                predicate = alwaysFalse()
//            case (.recipeEditor, .all):
//                predicate = #Predicate { item in
//                    item.isFavorite == true && !item.isRecipe && !item.isMenu &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            case (.menuEditor, .menus):
//                predicate = alwaysFalse()
//            case (.menuEditor, .recipes):
//                predicate = #Predicate { item in
//                    item.isFavorite == true && !item.isMenu && item.isRecipe == true &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            case (.menuEditor, .all):
//                predicate = #Predicate { item in
//                    item.isFavorite == true && !item.isMenu &&
//                    (needle.isEmpty || item.nameNormalized.contains(needle)) &&
//                    (excluded.isEmpty || !excluded.contains(item.id)) &&
//                    (capturedAge == nil || item.minAgeMonths <= capturedAge!)
//                }
//            }
//            
//            var favorites = (try? bg.fetch(FetchDescriptor<FoodItem>(predicate: predicate))) ?? []
//            
//            if !dietIDs.isEmpty || !allergenIDs.isEmpty {
//                favorites = favorites.filter { item in
//                    let itemDietIDs     = Set((item.diets ?? []).map(\.id))
//                    let itemAllergenIDs = Set((item.allergens ?? []).map(\.id))
//                    let hasAllDiets = dietIDs.allSatisfy { itemDietIDs.contains($0) }
//                    let hasNoBlockedAllergens = itemAllergenIDs.isDisjoint(with: allergenIDs)
//                    return hasAllDiets && hasNoBlockedAllergens
//                }
//            }
//            
//            // ← ДОБАВЕНО: само user-added ако е включено
//            if onlyUserAdded {
//                favorites = favorites.filter { $0.isUserAdded }
//            }
//            
//            if let nutrientID = capturedNutrientID {
//                favorites.sort { a, b in
//                    let va = self.nutrientValue(for: a, nutrientID: nutrientID) ?? -1
//                    let vb = self.nutrientValue(for: b, nutrientID: nutrientID) ?? -1
//                    return va > vb
//                }
//            } else {
//                favorites.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
//            }
//            
//            if Task.isCancelled { return }
//            
//            await MainActor.run { [weak self] in
//                guard let self = self, gen == self.generation else { return }
//                let existing = Set(self.favoriteItems.map(\.id))
//                self.favoriteItems.append(contentsOf: favorites.filter { !existing.contains($0.id) })
//                self.hasMore = false
//                self.setLoading(false)
//            }
//        }
//    }
//    
//    
//    private func loadTextPage() {
//        guard let container, !isLoading else { return }
//        setLoading(true, label: "text")
//        cancelInFlight()
//        
//        let needle    = query.foldedSearchKey
//        let excluded  = excludedIDs
//        let pageSize  = self.pageSize
//        let startOff  = self.startsOffset
//        let contOff   = self.containsOffset
//        let context   = self.searchContext
//        let capturedAge = self.profileAgeInMonths
//        let onlyUserAdded = self.onlyUserAdded
//        
//        let filterIDs: [String] = vitaminFilters.map { "vit_\($0)" } + mineralFilters.map { "min_\($0)" }
//        
//        let dietIDs     = Set(dietFilters.map(\.id))
//        let allergenIDs = Set(allergenFilters.map(\.id))
//        
//        enum TypeFilter { case all, recipes, menus }
//        let typeFilter: TypeFilter = showRecipesOnly ? .recipes : (showMenusOnly ? .menus : .all)
//        
//        let gen = self.generation   // capture generation
//        
//        currentTask = Task.detached { [weak self] in
//            guard let self = self else { return }
//            let bg = ModelContext(container)
//            bg.autosaveEnabled = false
//            
//            // 1) allowedIDs – сечение на избраните нутриенти
//            var allowedIDs: Set<Int>? = nil
//            if !filterIDs.isEmpty {
//                var running: Set<Int>? = nil
//                for nid in filterIDs {
//                    let d = FetchDescriptor<NutrientIndex>(predicate: #Predicate { $0.nutrientID == nid })
//                    if let idx = try? bg.fetch(d).first {
//                        let s = Set(idx.rankedFoods.map(\.foodID))
//                        running = (running == nil) ? s : running!.intersection(s)
//                    } else {
//                        running = []
//                    }
//                    if running?.isEmpty == true { break }
//                }
//                allowedIDs = running
//            }
//            
//            let isEmptyNeedle = needle.isEmpty
//            
//            // 2) Малки предикати по клон
//            func pred(prefix: Bool) -> Predicate<FoodItem> {
//                switch (context, typeFilter, isEmptyNeedle, prefix) {
//                    
//                    // --- .none ---
//                case (.none, .all, true, _):
//                    return #Predicate { f in !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .recipes, true, _):
//                    return #Predicate { f in f.isRecipe == true && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .menus, true, _):
//                    return #Predicate { f in f.isMenu == true && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .all, false, true):
//                    return #Predicate { f in f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .all, false, false):
//                    return #Predicate { f in f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .recipes, false, true):
//                    return #Predicate { f in f.isRecipe == true && f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .recipes, false, false):
//                    return #Predicate { f in f.isRecipe == true && f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .menus, false, true):
//                    return #Predicate { f in f.isMenu == true && f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.none, .menus, false, false):
//                    return #Predicate { f in f.isMenu == true && f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                    // --- .recipeEditor: не допуска рецепти/менюта ---
//                case (.recipeEditor, .recipes, _, _), (.recipeEditor, .menus, _, _):
//                    return #Predicate { _ in false }
//                    
//                case (.recipeEditor, .all, true, _):
//                    return #Predicate { f in !f.isRecipe && !f.isMenu && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.recipeEditor, .all, false, true):
//                    return #Predicate { f in !f.isRecipe && !f.isMenu && f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.recipeEditor, .all, false, false):
//                    return #Predicate { f in !f.isRecipe && !f.isMenu && f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                    // --- .menuEditor: не допуска менюта ---
//                case (.menuEditor, .menus, _, _):
//                    return #Predicate { _ in false }
//                    
//                case (.menuEditor, .recipes, true, _):
//                    return #Predicate { f in f.isRecipe == true && !f.isMenu && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.menuEditor, .recipes, false, true):
//                    return #Predicate { f in f.isRecipe == true && !f.isMenu && f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.menuEditor, .recipes, false, false):
//                    return #Predicate { f in f.isRecipe == true && !f.isMenu && f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.menuEditor, .all, true, _):
//                    return #Predicate { f in !f.isMenu && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.menuEditor, .all, false, true):
//                    return #Predicate { f in !f.isMenu && f.nameNormalized.starts(with: needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                    
//                case (.menuEditor, .all, false, false):
//                    return #Predicate { f in !f.isMenu && f.nameNormalized.contains(needle) && !excluded.contains(f.id) && (capturedAge == nil || f.minAgeMonths <= capturedAge!) }
//                }
//            }
//            
//            // 3) allowedIDs in-memory
//            func passesAllowed(_ f: FoodItem) -> Bool {
//                guard let allowed = allowedIDs else { return true }
//                switch context {
//                case .none:         return allowed.contains(f.id) || f.isRecipe || f.isMenu
//                case .recipeEditor: return allowed.contains(f.id)
//                case .menuEditor:   return allowed.contains(f.id) || f.isRecipe
//                }
//            }
//            
//            var resultsIDs: [Int] = []
//            var nextStarts = startOff
//            var nextContains = contOff
//            var lastStartsRaw = 0
//            var lastContainsRaw = 0
//            
//            // 4) STARTS
//            while resultsIDs.count < pageSize {
//                var d = FetchDescriptor<FoodItem>(predicate: pred(prefix: true),
//                                                  sortBy: [SortDescriptor(\.name)])
//                d.fetchLimit  = pageSize
//                d.fetchOffset = nextStarts
//                let raw = (try? bg.fetch(d)) ?? []
//                lastStartsRaw = raw.count
//                if raw.isEmpty { break }
//                nextStarts += raw.count
//                
//                for f in raw where passesAllowed(f) {
//                    resultsIDs.append(f.id)
//                    if resultsIDs.count == pageSize { break }
//                }
//                if resultsIDs.count == pageSize { break }
//            }
//            
//            // 5) CONTAINS
//            if resultsIDs.count < pageSize {
//                while resultsIDs.count < pageSize {
//                    var d = FetchDescriptor<FoodItem>(predicate: pred(prefix: false),
//                                                      sortBy: [SortDescriptor(\.name)])
//                    d.fetchLimit  = pageSize
//                    d.fetchOffset = nextContains
//                    let raw = (try? bg.fetch(d)) ?? []
//                    lastContainsRaw = raw.count
//                    if raw.isEmpty { break }
//                    nextContains += raw.count
//                    
//                    for f in raw {
//                        if !isEmptyNeedle && f.nameNormalized.starts(with: needle) { continue }
//                        if passesAllowed(f) {
//                            resultsIDs.append(f.id)
//                            if resultsIDs.count == pageSize { break }
//                        }
//                    }
//                    if resultsIDs.count == pageSize { break }
//                }
//            }
//            
//            if Task.isCancelled { return }
//            
//            let hasMore = (lastStartsRaw == pageSize) || (lastContainsRaw == pageSize)
//            var order: [Int : Int] = [:]
//            for (i, id) in resultsIDs.enumerated() { order[id] = i }
//            
//            await MainActor.run { [weak self] in
//                guard let self = self, let ctx = self.ctx, gen == self.generation else { return }
//                
//                if !resultsIDs.isEmpty {
//                    let idSet = Set(resultsIDs)
//                    let d = FetchDescriptor<FoodItem>(predicate: #Predicate { idSet.contains($0.id) })
//                    if let objs = try? ctx.fetch(d) {
//                        var filtered = self.applyDietAllergenFilters(objs,
//                                                                     dietIDs: dietIDs,
//                                                                     allergenIDs: allergenIDs)
//                        if onlyUserAdded { filtered = filtered.filter { $0.isUserAdded } } // ← ДОБАВЕНО
//                        self.appendUniquePreservingOrder(filtered, order: order)
//                    }
//                }
//                self.startsOffset   = nextStarts
//                self.containsOffset = nextContains
//                self.hasMore = hasMore
//                print("[StorageSearchVM] text page: ids=\(resultsIDs.count) startsOff=\(self.startsOffset) containsOff=\(self.containsOffset) hasMore=\(self.hasMore)")
//                self.setLoading(false)
//            }
//        }
//    }
//    
//    
//    // MARK: - Nutrient Search (paging) with generation + dedup
//    private func loadFirstNutrientPage(search: String) {
//        nutrientOffset = 0
//        items = []
//        loadMoreNutrientPage()
//    }
//    
//    private func loadMoreNutrientPage() {
//        loadMoreNutrient(search: query)
//    }
//    
//    private func loadMoreNutrient(search: String) {
//        guard let container, let nutrientID = selectedNutrientID, !isLoading else { return }
//        setLoading(true, label: "nutrient-search")
//        cancelInFlight()
//        
//        let needle    = search.foldedSearchKey
//        let excluded  = Set(excludedIDs.map { Int($0) })
//        let offset    = self.nutrientOffset
//        let limit     = nutrientPage
//        let context   = self.searchContext
//        let capturedAge = self.profileAgeInMonths
//        let onlyUserAdded = self.onlyUserAdded
//        
//        let dietIDs     = Set(dietFilters.map(\.id))
//        let allergenIDs = Set(allergenFilters.map(\.id))
//        
//        enum TypeFilter { case all, recipes, menus }
//        let typeFilter: TypeFilter = showRecipesOnly ? .recipes : (showMenusOnly ? .menus : .all)
//        
//        let gen = self.generation   // capture generation
//        
//        currentTask = Task.detached { [weak self] in
//            guard let self = self else { return }
//            let bg = ModelContext(container); bg.autosaveEnabled = false
//            
//            let idxDesc = FetchDescriptor<NutrientIndex>(predicate: #Predicate { $0.nutrientID == nutrientID })
//            guard let idx = try? bg.fetch(idxDesc).first else {
//                await MainActor.run { [weak self] in
//                    guard let self = self, gen == self.generation else { return }
//                    self.hasMore = false
//                    self.setLoading(false)
//                }
//                return
//            }
//            
//            let ids = NutrientIndex.pagedIDs(
//                from: idx.rankedFoods,
//                matching: needle,
//                excluding: excluded,
//                offset: offset,
//                limit: limit
//            )
//            
//            var order: [Int : Int] = [:]
//            for (i, id) in ids.enumerated() { order[id] = i + offset }
//            
//            let hasMoreResults = (ids.count == limit)
//            
//            if Task.isCancelled { return }
//            
//            await MainActor.run { [weak self] in
//                guard let self = self, let ctx = self.ctx, gen == self.generation else { return }
//                
//                if !ids.isEmpty {
//                    let idSet = Set(ids)
//                    let d: FetchDescriptor<FoodItem>
//                    
//                    switch (context, typeFilter) {
//                    case (.none, .all):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.none, .recipes):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && item.isRecipe == true && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.none, .menus):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && item.isMenu == true && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.recipeEditor, .all):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && !item.isRecipe && !item.isMenu && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.recipeEditor, .recipes), (.recipeEditor, .menus):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { _ in false })
//                    case (.menuEditor, .all):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && !item.isMenu && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.menuEditor, .recipes):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { item in idSet.contains(item.id) && !item.isMenu && item.isRecipe == true && (capturedAge == nil || item.minAgeMonths <= capturedAge!) })
//                    case (.menuEditor, .menus):
//                        d = FetchDescriptor<FoodItem>(predicate: #Predicate { _ in false })
//                    }
//                    
//                    if let objs = try? ctx.fetch(d) {
//                        var filtered = self.applyDietAllergenFilters(objs, dietIDs: dietIDs, allergenIDs: allergenIDs)
//                        if onlyUserAdded { filtered = filtered.filter { $0.isUserAdded } } // ← ДОБАВЕНО
//                        self.appendUniquePreservingOrder(filtered, order: order)
//                    }
//                }
//                
//                self.nutrientOffset += ids.count
//                self.hasMore = hasMoreResults
//                self.setLoading(false)
//            }
//        }
//    }
//    
//    
//    // MARK: - Filters setters
//    func setDietFilters(_ diets: [Diet]) { self.dietFilters = Set(diets) }
//    func setAllergenFilters(_ allergens: [Allergen]) { self.allergenFilters = Set(allergens) }
//}
