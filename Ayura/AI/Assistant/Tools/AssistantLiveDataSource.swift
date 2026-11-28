import Foundation
import SwiftData

/// The tools' view of the real app: the catalogue search, the profile's
/// calendar (where a day's meals live), the constitution store and the
/// existing AI generators.
@MainActor
final class AssistantLiveDataSource: AssistantDataSource {
    let profileModel: Profile
    let container: ModelContainer
    private let search: AssistantCatalogueSearch
    private var byName: [String: CompactFoodItem] = [:]

    init(profile: Profile, container: ModelContainer) {
        self.profileModel = profile
        self.container = container
        self.search = AssistantCatalogueSearch(container: container)
    }

    var profile: AssistantProfileSnapshot {
        let record = AyurvedaConstitutionStore.record(for: profileModel.id)
        return AssistantProfileSnapshot(
            profileID: profileModel.id,
            age: profileModel.age,
            sex: profileModel.gender,
            heightCm: profileModel.height,
            weightKg: profileModel.weight,
            allergens: profileModel.allergens,
            constitutionLabel: record?.result.label,
            constitution: record?.prakriti,
            priorityNutrients: profileModel.priorityVitamins.map(\.name) + profileModel.priorityMinerals.map(\.name),
            mealNames: profileModel.meals.sorted { $0.startTime < $1.startTime }.map(\.name)
        )
    }

    // MARK: Foods

    private func ensureIndex() async {
        await SearchIndexStore.shared.ensureLoaded(container: container)
        if byName.isEmpty {
            byName = Dictionary(
                SearchIndexStore.shared.compactFoods.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first })
        }
    }

    func searchFoods(_ query: String, limit: Int) async -> [CompactFoodItem] {
        await search.search(query, limit: limit)
    }

    func food(id: UUID) async -> CompactFoodItem? {
        await ensureIndex()
        return SearchIndexStore.shared.compactMap[id].map(search.withNutrients)
    }

    func food(named name: String) async -> CompactFoodItem? {
        await ensureIndex()
        return byName[name].map(search.withNutrients)
    }

    // MARK: Day

    func meals(on day: Date) async -> [AssistantMealRecord] {
        let events = await CalendarViewModel.shared.meals(forProfile: profileModel, on: day)
        var records = events.map { meal in
            AssistantMealRecord(
                name: meal.name, start: meal.startTime, end: meal.endTime,
                eventID: meal.calendarEventID, items: Self.items(fromNotes: meal.notes))
        }
        for template in profileModel.meals where !records.contains(where: { $0.name == template.name }) {
            let placed = template.detached(for: day)
            records.append(.init(name: placed.name, start: placed.startTime, end: placed.endTime, eventID: nil, items: []))
        }
        return records.sorted { $0.start < $1.start }
    }

    func save(_ meal: AssistantMealRecord, on day: Date) async -> AssistantMealRecord? {
        let items = meal.items.filter { $0.grams > 0 }
        if items.isEmpty {
            if let id = meal.eventID {
                _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: id)
            }
            NotificationCenter.default.post(name: .mealTimeDidChange, object: nil)
            var cleared = meal
            cleared.eventID = nil
            cleared.items = []
            return cleared
        }
        let (ok, eventID) = await CalendarViewModel.shared.createEvent(
            forProfile: profileModel,
            startDate: meal.start,
            endDate: meal.end,
            title: meal.name,
            invisiblePayload: Self.payload(for: items),
            existingEventID: meal.eventID)
        guard ok else { return nil }
        NotificationCenter.default.post(name: .mealTimeDidChange, object: nil)
        var saved = meal
        saved.eventID = eventID
        saved.items = items
        return saved
    }

    /// The same invisible payload the nutrition screen writes: "name=grams|…".
    static func payload(for items: [AssistantLoggedItem]) -> String {
        let visible = items
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.grams)" }
            .joined(separator: "|")
        return OptimizedInvisibleCoder.encode(from: visible) ?? ""
    }

    /// `Meal(event:)` decodes the payload to lines "name – 12 g".
    static func items(fromNotes notes: String?) -> [AssistantLoggedItem] {
        guard let notes, !notes.isEmpty else { return [] }
        return notes.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "–", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            let gramsText = parts[1].replacingOccurrences(of: "g", with: "").trimmingCharacters(in: .whitespaces)
            guard let grams = GlobalState.double(from: gramsText) ?? Double(gramsText) else { return nil }
            return AssistantLoggedItem(name: parts[0], grams: grams)
        }
    }

    // MARK: Constraints and constitution

    func constraints() -> [DietaryConstraint] {
        DietaryConstraintStore.constraints(for: profileModel.id)
    }

    func mergeConstraints(_ constraints: [DietaryConstraint]) {
        DietaryConstraintStore.merge(constraints, for: profileModel.id)
    }

    func saveConstitution(answers: [AyurvedaDosha]) {
        let result = AyurvedaConstitutionResult.from(answers: answers)
        AyurvedaConstitutionStore.save(
            AyurvedaConstitutionDraft(
                source: .questionnaire,
                prakriti: result.distribution,
                declaredTypeID: nil,
                questionnaireAnswers: answers),
            for: profileModel.id)
    }

    // MARK: Generators

    func startRecipe(named name: String) -> Bool {
        guard GlobalState.isAppleIntelligenceAvailable else { return false }
        return AIManager.shared.startRecipeGeneration(for: profileModel, recipeName: name, jobType: .recipeGeneration) != nil
    }

    func startFood(named name: String) -> Bool {
        guard GlobalState.isAppleIntelligenceAvailable else { return false }
        return AIManager.shared.startFoodDetailGeneration(for: profileModel, foodName: name, jobType: .foodItemDetail) != nil
    }

    func startMealPlan(days: Int, notes: [String]) -> Bool {
        guard GlobalState.isAppleIntelligenceAvailable else { return false }
        let mealNames = profileModel.meals.sorted { $0.startTime < $1.startTime }.map(\.name)
        guard !mealNames.isEmpty else { return false }
        let daysAndMeals = (1...max(1, days)).reduce(into: [Int: [String]]()) { $0[$1] = mealNames }
        return AIManager.shared.startPlanFill(
            for: profileModel,
            daysAndMeals: daysAndMeals,
            existingMeals: [:],
            selectedPrompts: notes.isEmpty ? nil : notes,
            jobType: days == 1 ? .dailyMealPlan : .mealPlan) != nil
    }

    // MARK: Practices and poses (read-only)

    func findPractices(_ query: String, limit: Int) -> [AssistantPracticeHit] {
        let ctx = container.mainContext
        let all: [Practice] = (try? ctx.fetch(FetchDescriptor<Practice>())) ?? []
        let words = Self.words(query)
        var scored: [(item: Practice, score: Int)] = []
        for p in all {
            let parts: [String] = [p.title, p.sanskrit ?? "", p.kind, p.practiceDescription] + p.goals + p.themes
            let hay = parts.joined(separator: " ").lowercased()
            let score = words.filter { hay.contains($0) }.count
            if words.isEmpty || score > 0 { scored.append((p, score)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.item.catalogNumber < b.item.catalogNumber }
        return scored.prefix(limit).map { pair in
            let p = pair.item
            return AssistantPracticeHit(
                id: p.id, title: p.title, kind: p.kind, minutes: max(1, p.durationSeconds / 60),
                goals: p.goals, dosha: "V\(p.doshaVata) P\(p.doshaPitta) K\(p.doshaKapha)")
        }
    }

    func findPoses(_ query: String, limit: Int) -> [AssistantPoseHit] {
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.slug != nil })
        let all: [ExerciseItem] = (try? ctx.fetch(descriptor)) ?? []
        let words = Self.words(query)
        var scored: [(item: ExerciseItem, score: Int)] = []
        for e in all {
            let parts: [String] = [e.name, e.sanskrit ?? "", e.exerciseDescription ?? ""]
            let hay = parts.joined(separator: " ").lowercased()
            let score = words.filter { hay.contains($0) }.count
            if words.isEmpty || score > 0 { scored.append((e, score)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.item.name < b.item.name }
        return scored.prefix(limit).map { pair in
            let e = pair.item
            return AssistantPoseHit(
                id: e.id, name: e.name, sanskrit: e.sanskrit, level: e.level,
                contraindications: e.contraindications ?? [])
        }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }
}

/// The app's food search, made once per assistant.
@MainActor
final class AssistantCatalogueSearch {
    let container: ModelContainer
    private var engine: SmartFoodSearch3?

    init(container: ModelContainer) {
        self.container = container
    }

    func search(_ query: String, limit: Int) async -> [CompactFoodItem] {
        let engine = self.engine ?? SmartFoodSearch3(container: container)
        self.engine = engine
        return await engine.searchCompact(query: query, limit: limit).map(withNutrients)
    }

    private var enriched: [UUID: CompactFoodItem] = [:]

    /// Recipes and menus carry no nutrient panel in the search index; their
    /// values come from the food record (aggregated over the ingredients, or
    /// the recipe's own panel when the ingredients have none).
    func withNutrients(_ food: CompactFoodItem) -> CompactFoodItem {
        guard (food.nutrientValues[.energy] ?? 0) <= 0, (food.nutrientValues[.protein] ?? 0) <= 0 else { return food }
        if let cached = enriched[food.id] { return cached }
        let id = food.id
        var descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? container.mainContext.fetch(descriptor).first else { return food }
        var values: [NutrientType: Double] = [:]
        for nutrient in [NutrientType.energy, .protein, .totalFat, .carbs, .fiber, .totalSugar, .sodium,
                         .saturatedFat, .potassium, .phosphorus, .calcium, .iron, .cholesterol, .vitaminK] {
            var v = item.calculatedValue(for: nutrient)
            if v <= 0 { v = item.value(for: nutrient) }
            if v > 0 { values[nutrient] = v }
        }
        if (values[.energy] ?? 0) <= 0 {
            let kcal = item.calories(for: item.referenceWeightG)
            if kcal > 0 { values[.energy] = kcal }
        }
        let made = CompactFoodItem(
            id: food.id, name: food.name, searchTokens: food.searchTokens, minAgeMonths: food.minAgeMonths,
            enforcedMinAgeMonths: food.enforcedMinAgeMonths, allergens: food.allergens, ph: food.ph,
            referenceWeightG: item.referenceWeightG, isRecipe: food.isRecipe, isMenu: food.isMenu,
            isFavorite: food.isFavorite, isEdible: food.isEdible, ayurvedaFacets: food.ayurvedaFacets,
            ayurvedaMetadata: food.ayurvedaMetadata, nutrientValues: values.isEmpty ? food.nutrientValues : values)
        enriched[food.id] = made
        return made
    }

}
