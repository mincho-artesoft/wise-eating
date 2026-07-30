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
    @Published private(set) var items: [ExerciseItem] = []
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private State
    private var context: ModelContext!
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 30

    private enum SearchPhase { case startsWith, contains, finished }
    private var searchPhase: SearchPhase = .startsWith
    private var startsWithOffset = 0
    private var containsOffset = 0

    // Де-дубликация през целия lifecycle на текущото зареждане
    private var seenIDs = Set<Int>()

    // За да избегнем двойно първоначално reset при .onAppear + Combine sink
    private var didInitialLoad = false

    // MARK: - Init
    init() {
        Publishers.CombineLatest($searchText.removeDuplicates(),
                                 $filter.removeDuplicates())
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.resetAndLoad()
            }
            .store(in: &cancellables)
    }

    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
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
        hasMore = false
        isLoading = false
        loadPage()
    }
    
    private func loadPage() {
        guard let context, !isLoading, searchPhase != .finished else { return }
        isLoading = true

        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let page = try context.fetch(descriptor)
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
                let page = try context.fetch(descriptor)
                fetchedItems.append(contentsOf: page)
                newContainsOffset += page.count
                if page.count < needed { newPhase = .finished }
            }

            // ✅ ДЕ-ДУБЛИКАЦИЯ ПРЕДИ append
            let uniqueNew = fetchedItems.filter { seenIDs.insert($0.id).inserted }

            self.items.append(contentsOf: uniqueNew)
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

    private func makePredicate(for phase: SearchPhase, search: String) -> Predicate<ExerciseItem> {
        let normalizedSearch = search.foldedSearchKey
        
        print("   🔎 makePredicate -> Filter: \(filter.rawValue), Phase: \(phase), Search: '\(search)'")

        if search.isEmpty {
            switch filter {
            case .all: return #Predicate<ExerciseItem> { $0.isUserAdded && !$0.isWorkout }
            case .favorites: return #Predicate<ExerciseItem> { $0.isFavorite }
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
                #Predicate<ExerciseItem> { $0.isFavorite && $0.nameNormalized.starts(with: normalizedSearch) } :
                #Predicate<ExerciseItem> { $0.isFavorite && $0.nameNormalized.contains(normalizedSearch) && !$0.nameNormalized.starts(with: normalizedSearch) }
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
        guard let context, item.isUserAdded else { return }
        context.delete(item)
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
        }
        try? context.save()
    }
    
    /// Обновява състоянието в паметта и ако сме във Favorites – прунва нефаворитните.
    func updateItemAndPruneFavorites(notification: Notification) {
        guard let toggledItem = notification.object as? ExerciseItem else { return }

        if let index = items.firstIndex(where: { $0.id == toggledItem.id }) {
            items[index].isFavorite = toggledItem.isFavorite
            print("✅ ExerciseListVM: Updated '\(items[index].name)' in-memory state. isFavorite is now \(items[index].isFavorite).")
        }

        if filter == .favorites {
            print("🧼 Pruning favorites list...")
            items.removeAll { !$0.isFavorite }
        }
    }
    
    func exerciseUsageCount(for item: ExerciseItem) -> Int {
        guard let context else { return 0 }

        let targetID = item.id

        let descriptor = FetchDescriptor<ExerciseLink>(
            predicate: #Predicate<ExerciseLink> { link in
                link.exercise?.id == targetID
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
        guard let context else { return }

        let targetID = item.id

        // 1) Намираме всички ExerciseLink, които сочат към това упражнение и ги трием
        let descriptor = FetchDescriptor<ExerciseLink>(
            predicate: #Predicate<ExerciseLink> { link in
                link.exercise?.id == targetID
            }
        )

        do {
            let links = try context.fetch(descriptor)
            if !links.isEmpty {
                print("🧹 Removing \(links.count) exercise links for exercise '\(item.name)'")
                for link in links {
                    context.delete(link)
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
                    link.exercise?.id == targetID
                }
            )

            // 2) Употреба в TrainingPlanExercise
            let inPlanDesc = FetchDescriptor<TrainingPlanExercise>(
                predicate: #Predicate<TrainingPlanExercise> { link in
                    link.exercise?.id == targetID
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
        guard let context else { return }

        let targetID = item.id   // 👈 Тук също

        do {
            // 1) ExerciseLink в workouts
            let workoutLinksDesc = FetchDescriptor<ExerciseLink>(
                predicate: #Predicate<ExerciseLink> { link in
                    link.exercise?.id == targetID
                }
            )
            let workoutLinks = try context.fetch(workoutLinksDesc)
            workoutLinks.forEach { context.delete($0) }
            
            // 2) TrainingPlanExercise в тренировъчни планове
            let planLinksDesc = FetchDescriptor<TrainingPlanExercise>(
                predicate: #Predicate<TrainingPlanExercise> { link in
                    link.exercise?.id == targetID
                }
            )
            let planLinks = try context.fetch(planLinksDesc)
            planLinks.forEach { context.delete($0) }
            
        } catch {
            print("❌ Failed to detach exercise from workouts/plans before delete: \(error)")
        }
        
        // Накрая – стандартното ти триене
        delete(item)
    }


}
