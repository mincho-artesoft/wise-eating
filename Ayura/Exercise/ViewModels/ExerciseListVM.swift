// Exercise/ViewModels/ExerciseListVM.swift

import Combine
import Foundation
import SwiftData

@MainActor
final class ExerciseListVM: ObservableObject {

    // MARK: - Filter Enum
    // --- НАЧАЛО НА ПРОМЯНАТА ---
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Exercises", workouts = "Workouts", plans = "Training Plans", favorites = "Favorites", `default` = "Default"
        var id: String { rawValue }
    }
    // --- КРАЙ НА ПРОМЯНАТА ---
    
    // MARK: - Inputs & Outputs
    @Published var searchText: String = ""
    @Published var filter: Filter = .all
    @Published var ayurvedaFilters: AyurvedaSearchFilters = .empty
    @Published private(set) var items: [ExerciseItem] = []
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private State
    private var context: ModelContext!
    private var userContext: ModelContext?
    private var userContainer: ModelContainer?
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 30

    private enum SearchPhase { case startsWith, contains, finished }
    private var searchPhase: SearchPhase = .startsWith
    private var startsWithOffset = 0
    private var containsOffset = 0
    private var ayurvedaOffset = 0

    // Де-дубликация през целия lifecycle на текущото зареждане
    private var seenIDs = Set<UUID>()

    // За да избегнем двойно първоначално reset при .onAppear + Combine sink
    private var didInitialLoad = false
    private var recentUserWrites: [UUID: ExerciseItem] = [:]
    private var recentUserWriteContexts: [UUID: ModelContext] = [:]

    // MARK: - Init
    init() {
        Publishers.CombineLatest3(
            $searchText.removeDuplicates(),
            $filter.removeDuplicates(),
            $ayurvedaFilters.removeDuplicates()
        )
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetAndLoad()
            }
            .store(in: &cancellables)
    }

    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
        self.userContext = try? CombinedStoreFactory.makeUserWriteContext(
            from: context.container
        )
        self.userContainer = self.userContext?.container
        try? CatalogPreferenceStore.shared.load(context: context)
    }

    /// Publishes the fresh user-store instance after an editor save, avoiding
    /// stale registered objects in the combined catalogue/user read context.
    func applyUserStoreWrite(_ item: ExerciseItem) {
        let displayItem: ExerciseItem
        if let savedContext = item.modelContext {
            userContext = savedContext
            recentUserWriteContexts[item.id] = savedContext
            displayItem = item
        } else if let userContainer {
            let freshContext = ModelContext(userContainer)
            freshContext.autosaveEnabled = false
            userContext = freshContext
            let itemID = item.id
            var descriptor = FetchDescriptor<ExerciseItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            displayItem = (try? freshContext.fetch(descriptor).first) ?? item
            recentUserWriteContexts[item.id] = freshContext
        } else {
            displayItem = item
        }

        recentUserWrites[displayItem.id] = displayItem
        items.removeAll { $0.id == displayItem.id }
        if shouldDisplayUserWrite(displayItem) {
            items.append(displayItem)
            items.sort { $0.nameNormalized < $1.nameNormalized }
        }
        isLoading = false
    }

    // Позволява на View да извика „първи“ load само веднъж
    func ensureInitialLoad(withInitialSearch search: String) {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        self.searchText = search
        resetAndLoad()
    }

    // MARK: - Loading Logic
    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        loadPage()
    }

    func resetAndLoad() {
        guard context != nil else { return }
        print("🔄 ExerciseListVM: resetAndLoad() triggered. Search: '\(searchText)', Filter: \(filter.rawValue)")
        items = []
        seenIDs.removeAll()
        searchPhase = .startsWith
        startsWithOffset = 0
        containsOffset = 0
        ayurvedaOffset = 0
        hasMore = false
        isLoading = false
        loadPage()
    }
    
    private func loadPage() {
        guard let context, !isLoading, searchPhase != .finished else { return }
        isLoading = true

        let readContext: ModelContext
        switch filter {
        case .all, .workouts:
            if let userContainer {
                let freshContext = ModelContext(userContainer)
                freshContext.autosaveEnabled = false
                userContext = freshContext
                readContext = freshContext
            } else {
                readContext = userContext ?? context
            }
        case .default, .favorites, .plans:
            readContext = context
        }

        let parsedQuery = ExerciseAyurvedaSearch.parse(searchText)
        let search = parsedQuery.lexicalQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usesAyurvedaRanking = ayurvedaFilters.isActive
            || !parsedQuery.constraints.isEmpty

        if usesAyurvedaRanking {
            loadAyurvedaPage(
                context: readContext,
                search: search,
                constraints: parsedQuery.constraints
            )
            return
        }

        let phase = self.searchPhase
        let startsOff = self.startsWithOffset
        let containsOff = self.containsOffset

        // Fetch от същия ModelContext (MainActor) → никакви race conditions и дублирания.
        do {
            var fetchedItems: [ExerciseItem] = []
            var newPhase = phase
            var newStartsOffset = startsOff
            var newContainsOffset = containsOff

            if newPhase == .startsWith {
                let predicate = self.makePredicate(for: .startsWith, search: search)
                var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.nameNormalized)])
                descriptor.fetchOffset = startsOff
                descriptor.fetchLimit = self.pageSize
                let page = try readContext.fetch(descriptor)
                fetchedItems.append(contentsOf: page)
                newStartsOffset += page.count
                if page.count < self.pageSize { newPhase = .contains }
            }

            if newPhase == .contains && fetchedItems.count < self.pageSize {
                let needed = self.pageSize - fetchedItems.count
                let predicate = self.makePredicate(for: .contains, search: search)
                var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.nameNormalized)])
                descriptor.fetchOffset = containsOff
                descriptor.fetchLimit = needed
                let page = try readContext.fetch(descriptor)
                fetchedItems.append(contentsOf: page)
                newContainsOffset += page.count
                if page.count < needed { newPhase = .finished }
            }

            // ✅ ДЕ-ДУБЛИКАЦИЯ ПРЕДИ append
            let uniqueNew = fetchedItems.filter { seenIDs.insert($0.id).inserted }

            self.items.append(contentsOf: uniqueNew)
            self.reconcileRecentUserWrites()
            self.searchPhase = newPhase
            self.startsWithOffset = newStartsOffset
            self.containsOffset = newContainsOffset
            self.hasMore = newPhase != .finished
        } catch {
            print("❌ ExerciseListVM.loadPage fetch error: \(error)")
            self.hasMore = false
        }

        self.isLoading = false
    }

    private func reconcileRecentUserWrites() {
        guard !ayurvedaFilters.isActive else { return }
        for item in recentUserWrites.values {
            items.removeAll { $0.id == item.id }
            if shouldDisplayUserWrite(item) {
                items.append(item)
                seenIDs.insert(item.id)
            }
        }
        items.sort { $0.nameNormalized < $1.nameNormalized }
    }

    private func shouldDisplayUserWrite(_ item: ExerciseItem) -> Bool {
        let matchesFilter: Bool
        switch filter {
        case .all:
            matchesFilter = item.isUserAdded && !item.isWorkout
        case .workouts:
            matchesFilter = item.isUserAdded && item.isWorkout
        case .favorites:
            matchesFilter = item.effectiveIsFavorite
        case .default, .plans:
            matchesFilter = false
        }
        guard matchesFilter else { return false }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !query.isEmpty else { return true }
        let normalizedName = item.name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        return normalizedName.contains(query)
    }

    private func loadAyurvedaPage(
        context: ModelContext,
        search: String,
        constraints: [AyurvedaFacetConstraint]
    ) {
        do {
            let startsWith = try context.fetch(
                FetchDescriptor(
                    predicate: makePredicate(for: .startsWith, search: search),
                    sortBy: [SortDescriptor(\.nameNormalized)]
                )
            )
            let contains = search.isEmpty
                ? []
                : try context.fetch(
                    FetchDescriptor(
                        predicate: makePredicate(for: .contains, search: search),
                        sortBy: [SortDescriptor(\.nameNormalized)]
                    )
                )

            var unique: [ExerciseItem] = []
            var uniqueIDs = Set<UUID>()
            for item in startsWith + contains where uniqueIDs.insert(item.id).inserted {
                unique.append(item)
            }

            let ranked = unique.sorted { lhs, rhs in
                let lhsScore = ExerciseAyurvedaSearch.score(
                    item: lhs,
                    filters: ayurvedaFilters,
                    constraints: constraints
                )
                let rhsScore = ExerciseAyurvedaSearch.score(
                    item: rhs,
                    filters: ayurvedaFilters,
                    constraints: constraints
                )
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.nameNormalized < rhs.nameNormalized
            }

            let page = ranked.dropFirst(ayurvedaOffset).prefix(pageSize)
            let uniqueNew = page.filter { seenIDs.insert($0.id).inserted }
            items.append(contentsOf: uniqueNew)
            ayurvedaOffset += page.count
            hasMore = ayurvedaOffset < ranked.count
            searchPhase = hasMore ? .startsWith : .finished
        } catch {
            print("❌ ExerciseListVM Ayurveda search error: \(error)")
            hasMore = false
            searchPhase = .finished
        }

        isLoading = false
    }

    private func makePredicate(for phase: SearchPhase, search: String) -> Predicate<ExerciseItem> {
        let normalizedSearch = search.foldedSearchKey
        let catalogFavoriteIDs = CatalogPreferenceStore.shared.favoriteIDs(
            kind: "exercise"
        )
        
        print("   🔎 makePredicate -> Filter: \(filter.rawValue), Phase: \(phase), Search: '\(search)'")

        if search.isEmpty {
            switch filter {
            case .all: return #Predicate<ExerciseItem> { $0.isUserAdded && !$0.isWorkout }
            case .favorites: return #Predicate<ExerciseItem> {
                $0.isFavorite || catalogFavoriteIDs.contains($0.id)
            }
            case .workouts: return #Predicate<ExerciseItem> { $0.isUserAdded && $0.isWorkout == true }
            case .default: return #Predicate<ExerciseItem> { !$0.isUserAdded }
            case .plans: return #Predicate<ExerciseItem> { _ in false } // Не връщаме нищо, защото се управлява от друг VM
            }
        }

        switch filter {
        case .all:
            return phase == .startsWith ?
                #Predicate<ExerciseItem> { $0.isUserAdded && !$0.isWorkout && $0.nameNormalized.starts(with: normalizedSearch) } :
                #Predicate<ExerciseItem> { $0.isUserAdded && !$0.isWorkout && $0.nameNormalized.contains(normalizedSearch) && !$0.nameNormalized.starts(with: normalizedSearch) }
        case .favorites:
            return phase == .startsWith ?
                #Predicate<ExerciseItem> { ($0.isFavorite || catalogFavoriteIDs.contains($0.id)) && $0.nameNormalized.starts(with: normalizedSearch) } :
                #Predicate<ExerciseItem> { ($0.isFavorite || catalogFavoriteIDs.contains($0.id)) && $0.nameNormalized.contains(normalizedSearch) && !$0.nameNormalized.starts(with: normalizedSearch) }
        case .workouts:
            return phase == .startsWith ?
                #Predicate<ExerciseItem> { $0.isUserAdded && $0.isWorkout == true && $0.nameNormalized.starts(with: normalizedSearch) } :
                #Predicate<ExerciseItem> { $0.isUserAdded && $0.isWorkout == true && $0.nameNormalized.contains(normalizedSearch) && !$0.nameNormalized.starts(with: normalizedSearch) }
        case .default:
            return phase == .startsWith ?
                #Predicate<ExerciseItem> { !$0.isUserAdded && $0.nameNormalized.starts(with: normalizedSearch) } :
                #Predicate<ExerciseItem> { !$0.isUserAdded && $0.nameNormalized.contains(normalizedSearch) && !$0.nameNormalized.starts(with: normalizedSearch) }
        case .plans:
            return #Predicate<ExerciseItem> { _ in false }
        }
    }

    // MARK: - CRUD
    func delete(_ item: ExerciseItem) {
        guard let userContext, item.isUserAdded else { return }
        let itemID = item.id

        do {
            guard let storedItem = try CatalogReferenceResolver.userExercise(
                id: itemID,
                context: userContext
            ) else {
                throw CatalogReferenceError.missingUserExercise(itemID)
            }

            userContext.delete(storedItem)
            try userContext.save()

            // Update the visible collection only after SQLite accepted the
            // deletion. This keeps a failed save from looking successful.
            items.removeAll { $0.id == itemID }
            recentUserWrites.removeValue(forKey: itemID)
            recentUserWriteContexts.removeValue(forKey: itemID)
        } catch {
            print("❌ Failed to delete exercise '\(item.name)': \(error)")
        }
    }
    
    /// Обновява състоянието в паметта и ако сме във Favorites – прунва нефаворитните.
    func updateItemAndPruneFavorites(notification: Notification) {
        guard let toggledItem = notification.object as? ExerciseItem else { return }

        if filter == .favorites {
            print("🧼 Pruning favorites list...")
            items.removeAll { !$0.effectiveIsFavorite }
        }
    }
    
    func exerciseUsageCount(for item: ExerciseItem) -> Int {
        guard let context else { return 0 }

        let targetID = item.id

        let descriptor = FetchDescriptor<ExerciseLink>(
            predicate: #Predicate<ExerciseLink> { link in
                link.persistedExercise?.id == targetID
                    || link.catalogExerciseID == targetID
            }
        )

        do {
            let links = try context.fetch(descriptor)
            return links.count
        } catch {
            print("❌ Failed to fetch exercise usage count: \(error)")
            return 0
        }
    }

    /// Изтрива упражнението, като преди това го маха от всички workouts (ExerciseLink)
    func deleteDetachingFromWorkouts(_ item: ExerciseItem) {
        guard let userContext else { return }

        let targetID = item.id

        // 1) Намираме всички ExerciseLink, които сочат към това упражнение и ги трием
        let descriptor = FetchDescriptor<ExerciseLink>(
            predicate: #Predicate<ExerciseLink> { link in
                link.persistedExercise?.id == targetID
                    || link.catalogExerciseID == targetID
            }
        )

        do {
            let links = try userContext.fetch(descriptor)
            if !links.isEmpty {
                print("🧹 Removing \(links.count) exercise links for exercise '\(item.name)'")
                for link in links {
                    userContext.delete(link)
                }
            }
        } catch {
            print("❌ Failed to detach exercise from workouts before delete: \(error)")
        }

        // 2) След като вече не се използва, трием самото упражнение
        delete(item)
    }
    
    // MARK: - Usage & Safe Delete Helpers

    // MARK: - Usage & Safe Delete Helpers

    func trainingUsageCount(for item: ExerciseItem) -> Int {
        guard let context else { return 0 }
        
        let targetID = item.id   // 👈 ВАЖНО

        do {
            // 1) Употреба в Workout-и (ExerciseLink.exercise)
            let inWorkoutsDesc = FetchDescriptor<ExerciseLink>(
                predicate: #Predicate<ExerciseLink> { link in
                    link.persistedExercise?.id == targetID
                        || link.catalogExerciseID == targetID
                }
            )

            // 2) Употреба в TrainingPlanExercise
            let inPlanDesc = FetchDescriptor<TrainingPlanExercise>(
                predicate: #Predicate<TrainingPlanExercise> { link in
                    link.persistedExercise?.id == targetID
                        || link.catalogExerciseID == targetID
                }
            )
            
            let count1 = try context.fetch(inWorkoutsDesc).count
            let count2 = try context.fetch(inPlanDesc).count
            return count1 + count2
        } catch {
            print("❌ Failed to fetch training usage count: \(error)")
            return 0
        }
    }

    func deleteDetachingFromWorkoutsAndPlans(_ item: ExerciseItem) {
        guard let userContext else { return }

        let targetID = item.id   // 👈 Тук също

        do {
            // 1) ExerciseLink в workouts
            let workoutLinksDesc = FetchDescriptor<ExerciseLink>(
                predicate: #Predicate<ExerciseLink> { link in
                    link.persistedExercise?.id == targetID
                        || link.catalogExerciseID == targetID
                }
            )
            let workoutLinks = try userContext.fetch(workoutLinksDesc)
            workoutLinks.forEach { userContext.delete($0) }
            
            // 2) TrainingPlanExercise в тренировъчни планове
            let planLinksDesc = FetchDescriptor<TrainingPlanExercise>(
                predicate: #Predicate<TrainingPlanExercise> { link in
                    link.persistedExercise?.id == targetID
                        || link.catalogExerciseID == targetID
                }
            )
            let planLinks = try userContext.fetch(planLinksDesc)
            planLinks.forEach { userContext.delete($0) }
            
        } catch {
            print("❌ Failed to detach exercise from workouts/plans before delete: \(error)")
        }
        
        // Накрая – стандартното ти триене
        delete(item)
    }


}
