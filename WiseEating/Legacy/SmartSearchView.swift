//import SwiftUI
//import SwiftData
//
//@available(iOS 26.0, *)
//struct SmartSearchView: View {
//    @Environment(\.modelContext) private var modelContext
//
//    private enum SearchDomain: String, CaseIterable, Identifiable {
//        case foods = "Foods"
//        case exercises = "Exercises"
//        var id: String { rawValue }
//        
//        var placeholder: String {
//            switch self {
//            case .foods: return "Search foods (e.g., 'banana yogurt')"
//            case .exercises: return "Search exercises (e.g., 'dumbbell shoulder press')"
//            }
//        }
//    }
//
//    @State private var domain: SearchDomain = .foods
//    @State private var query: String = ""
//
//    // Отделни резултатни масиви
//    @State private var foodResults: [FoodItem] = []
//    @State private var exerciseResults: [ExerciseItem] = []
//    
//    // Задача за дебоунс
//    @State private var searchTask: Task<Void, Never>? = nil
//    
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 12) {
//                // Горен сегмент за избор на домейн
//                Picker("Domain", selection: $domain) {
//                    ForEach(SearchDomain.allCases) { d in
//                        Text(d.rawValue).tag(d)
//                    }
//                }
//                .pickerStyle(.segmented)
//                .padding(.horizontal)
//
//                // Поле за търсене
//                TextField(domain.placeholder, text: $query)
//                    .textFieldStyle(.roundedBorder)
//                    .autocorrectionDisabled(true)
//                    .textInputAutocapitalization(.never)
//                    .padding(.horizontal)
//                    .onChange(of: query) { _, newQuery in
//                        // Отменяме предходната задача
//                        searchTask?.cancel()
//
//                        // Празна заявка => чистим резултати
//                        guard !newQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
//                            foodResults = []
//                            exerciseResults = []
//                            return
//                        }
//
//                        // Дебоунс (400 ms)
//                        searchTask = Task {
//                            do {
//                                try await Task.sleep(for: .milliseconds(400))
//                                await performSearch(query: newQuery, in: domain)
//                            } catch { /* отменена задача е нормално поведение */ }
//                        }
//                    }
//                    .onChange(of: domain) { _, newDomain in
//                        // При смяна на домейна – ребилдваме търсенето за текущия текст (ако не е празно)
//                        searchTask?.cancel()
//                        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
//                            foodResults = []
//                            exerciseResults = []
//                            return
//                        }
//                        searchTask = Task {
//                            do {
//                                try await Task.sleep(for: .milliseconds(150)) // по-малък дебоунс при смяна на таб
//                                await performSearch(query: query, in: newDomain)
//                            } catch { }
//                        }
//                    }
//
//                // Един List, който показва различни редове според домейна
//                List {
//                    if domain == .foods {
//                        ForEach(foodResults) { food in
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(food.name).fontWeight(.semibold)
//                                if !food.searchTokens.isEmpty {
//                                    Text(food.searchTokens.joined(separator: ", "))
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }
//                            }
//                        }
//                    } else {
//                        ForEach(exerciseResults) { ex in
//                            VStack(alignment: .leading, spacing: 4) {
//                                Text(ex.name).fontWeight(.semibold)
//                                if !ex.searchTokens.isEmpty {
//                                    Text(ex.searchTokens.joined(separator: ", "))
//                                        .font(.caption)
//                                        .foregroundStyle(.secondary)
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//            .navigationTitle("Smart Search Test")
//        }
//    }
//
//    // MARK: - Search
//    private func performSearch(query: String, in domain: SearchDomain) async {
//        let container = modelContext.container
//
//        switch domain {
//        case .foods:
//            let smartFoodSearch = SmartFoodSearch(container: container)
//            let resultIDs = await smartFoodSearch.searchFoodsAI(query: query)
//
//            if !Task.isCancelled {
//                await MainActor.run {
//                    let items = resultIDs.compactMap { id in
//                        modelContext.model(for: id) as? FoodItem
//                    }
//                    self.foodResults = sortByQuery(items, query: query) { $0.name }
//                }
//            }
//
//        case .exercises:
//            let smartExerciseSearch = SmartExerciseSearch(container: container)
//            let resultIDs = await smartExerciseSearch.searchExercisesAI(query: query)
//
//            if !Task.isCancelled {
//                await MainActor.run {
//                    let items = resultIDs.compactMap { id in
//                        modelContext.model(for: id) as? ExerciseItem
//                    }
//                    self.exerciseResults = sortByQuery(items, query: query) { $0.name }
//                }
//            }
//        }
//    }
//
//    private func sortByQuery<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
//        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
//        let lowerQuery = trimmedQuery.lowercased()
//
//        guard !lowerQuery.isEmpty else {
//            // No query: simple alphanumerical sort by name
//            return items.sorted { lhs, rhs in
//                name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
//            }
//        }
//
//        func bucket(for item: T) -> Int {
//            let n = name(item).lowercased()
//            if n.hasPrefix(lowerQuery) {
//                // 0: exact match from beginning
//                return 0
//            } else if n.contains(lowerQuery) {
//                // 1: match somewhere inside the name
//                return 1
//            } else {
//                // 2: everything else
//                return 2
//            }
//        }
//
//        return items.sorted { lhs, rhs in
//            let bl = bucket(for: lhs)
//            let br = bucket(for: rhs)
//            if bl != br { return bl < br }
//            // Same bucket: alphanumerical by name
//            return name(lhs).localizedStandardCompare(name(rhs)) == .orderedAscending
//        }
//    }
//}
