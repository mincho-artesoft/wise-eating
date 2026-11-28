import Foundation

/// The only things the assistant can do. Each tool is a plain function over the
/// app's data; `call(_:arguments:)` is the single entry used by both engines, so
/// the on-device model and the OpenAI model behave the same and only the brain
/// differs. Read tools answer at once; write tools return a preview and queue an
/// `AssistantPendingAction` that the person confirms.
@MainActor
final class AssistantToolbox {
    enum Tool: String, CaseIterable, Sendable {
        case searchFoods = "search_foods"
        case getDay = "get_day"
        case logFood = "log_food"
        case removeLoggedFood = "remove_logged_food"
        case getProfile = "get_profile"
        case getDietaryConstraints = "get_dietary_constraints"
        case setDietaryConstraints = "set_dietary_constraints"
        case createRecipe = "create_recipe"
        case createFood = "create_food"
        case createMealPlan = "create_meal_plan"
        case setConstitution = "set_constitution"
        case findPractice = "find_practice"
        case findPose = "find_pose"

        var isWrite: Bool {
            switch self {
            case .logFood, .removeLoggedFood, .setDietaryConstraints, .createRecipe,
                 .createFood, .createMealPlan, .setConstitution: true
            default: false
            }
        }
    }

    let data: AssistantDataSource
    private(set) var pending: [AssistantPendingAction] = []
    private(set) var lastUndo: AssistantUndo?
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    init(data: AssistantDataSource) {
        self.data = data
    }

    // MARK: - Entry point

    /// Runs a tool with JSON arguments and returns a JSON string for the model.
    /// Unknown tools and bad arguments come back as `{"error": …}`, never a throw.
    func call(_ name: String, arguments: String) async -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        guard let tool = Tool(rawValue: name) else {
            return Self.json(["error": "unknown tool \(name)"])
        }
        let result: [String: Any]
        switch tool {
        case .searchFoods: result = await searchFoods(args)
        case .getDay: result = await getDay(args)
        case .logFood: result = await logFood(args)
        case .removeLoggedFood: result = await removeLoggedFood(args)
        case .getProfile: result = getProfile()
        case .getDietaryConstraints: result = ["constraints": data.constraints().map(Self.constraintJSON)]
        case .setDietaryConstraints: result = setDietaryConstraints(args)
        case .createRecipe: result = createNamed(args, kind: .recipe)
        case .createFood: result = createNamed(args, kind: .food)
        case .createMealPlan: result = createMealPlan(args)
        case .setConstitution: result = setConstitution(args)
        case .findPractice: result = findPractice(args)
        case .findPose: result = findPose(args)
        }
        return Self.json(result)
    }

    // MARK: - Read tools

    func searchFoods(_ args: [String: Any]) async -> [String: Any] {
        let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ["error": "query is required"] }
        let limit = min(max(Self.int(args["limit"]) ?? 8, 1), 20)
        let filters = args["filters"] as? [String: Any] ?? [:]
        let excludeAllergens = filters["exclude_allergens"] as? Bool ?? true
        let maxPer100 = (filters["max_per_100g"] as? [String: Any] ?? [:])
            .compactMapValues(Self.double)

        let found = await data.searchFoods(query, limit: limit * 3)
        let constraints = data.constraints()
        var rows: [[String: Any]] = []
        for food in found where food.isEdible {
            let allergyHit = allergenHit(food)
            if excludeAllergens, allergyHit != nil { continue }
            let per100 = food.per100g
            let tooHigh = maxPer100.contains { key, limit in
                NutrientType(rawValue: key).map { (per100[$0] ?? 0) > limit } ?? false
            }
            if tooHigh { continue }
            var row = Self.foodJSON(food)
            if let allergyHit { row["allergy"] = allergyHit }
            if let rule = constraints.first(where: { $0.kind == .excludeFood && DietaryConstraintChecker.matches(foodName: food.name, term: $0.foodTerm ?? "") }) {
                row["avoided"] = rule.summary
            }
            rows.append(row)
            if rows.count >= limit { break }
        }
        return ["query": query, "results": rows]
    }

    func getDay(_ args: [String: Any]) async -> [String: Any] {
        let day = parseDay(args["date"])
        let meals = await data.meals(on: day)
        var allFoods: [CheckedFood] = []
        var mealRows: [[String: Any]] = []
        for meal in meals {
            var itemRows: [[String: Any]] = []
            for item in meal.items {
                let food = await data.food(named: item.name)
                if let food { allFoods.append(food.checked(grams: item.grams, meal: meal.name)) }
                itemRows.append([
                    "name": item.name,
                    "grams": Self.round(item.grams),
                    "kcal": Self.round(food.map { ($0.per100g[.energy] ?? 0) * item.grams / 100 } ?? 0),
                    "protein_g": Self.round(food.map { ($0.per100g[.protein] ?? 0) * item.grams / 100 } ?? 0),
                ])
            }
            mealRows.append(["meal": meal.name, "items": itemRows])
        }
        let report = DietaryConstraintChecker.check(
            foods: allFoods, constraints: data.constraints(),
            allergens: data.profile.allergens, isCompleteDay: false)
        return [
            "date": Self.dayString(day, calendar: calendar),
            "meals": mealRows,
            "totals": Self.totalsJSON(report.totals),
            "warnings": report.violations.map(\.message),
        ]
    }

    func getProfile() -> [String: Any] {
        let p = data.profile
        var row: [String: Any] = [
            "age": p.age,
            "sex": p.sex,
            "height_cm": Self.round(p.heightCm),
            "weight_kg": Self.round(p.weightKg),
            "allergens": p.allergens.map(\.rawValue),
            "meals": p.mealNames,
            "priority_nutrients": p.priorityNutrients,
            "dietary_constraints": data.constraints().map(\.summary),
        ]
        if let label = p.constitutionLabel { row["constitution"] = label }
        if let d = p.constitution {
            row["constitution_distribution"] = ["vata": Self.round(d.vata), "pitta": Self.round(d.pitta), "kapha": Self.round(d.kapha)]
        }
        return row
    }

    func findPractice(_ args: [String: Any]) -> [String: Any] {
        let query = args["query"] as? String ?? ""
        let rows = data.findPractices(query, limit: min(Self.int(args["limit"]) ?? 5, 10)).map {
            ["id": $0.id.uuidString, "title": $0.title, "kind": $0.kind, "minutes": $0.minutes, "goals": $0.goals, "dosha": $0.dosha] as [String: Any]
        }
        return ["results": rows]
    }

    func findPose(_ args: [String: Any]) -> [String: Any] {
        let query = args["query"] as? String ?? ""
        let rows = data.findPoses(query, limit: min(Self.int(args["limit"]) ?? 5, 10)).map {
            var r: [String: Any] = ["id": $0.id.uuidString, "name": $0.name, "contraindications": $0.contraindications]
            if let s = $0.sanskrit { r["sanskrit"] = s }
            if let l = $0.level { r["level"] = l }
            return r
        }
        return ["results": rows]
    }

    // MARK: - Write tools (previews)

    func logFood(_ args: [String: Any]) async -> [String: Any] {
        var rawItems = args["items"] as? [[String: Any]] ?? []
        if rawItems.isEmpty, args["food_id"] != nil {
            rawItems = [["food_id": args["food_id"] as Any, "grams": args["grams"] as Any]]
        }
        guard !rawItems.isEmpty else { return ["error": "items are required"] }
        let day = parseDay(args["date"])
        let meals = await data.meals(on: day)
        guard let mealName = resolveMeal(args["meal"] as? String, in: meals, day: day) else {
            return ["error": "no meal found; meals are \(meals.map(\.name))"]
        }

        var proposed: [AssistantProposedItem] = []
        var newFoods: [CheckedFood] = []
        for raw in rawItems {
            guard let idString = raw["food_id"] as? String, let id = UUID(uuidString: idString),
                  let food = await data.food(id: id) else {
                return ["error": "unknown food_id \(raw["food_id"] ?? ""); call search_foods first"]
            }
            guard let grams = Self.double(raw["grams"]), grams > 0, grams <= 3000 else {
                return ["error": "grams must be between 1 and 3000 for \(food.name)"]
            }
            let per100 = food.per100g
            proposed.append(.init(
                foodID: food.id, name: food.name, grams: grams,
                kcal: (per100[.energy] ?? 0) * grams / 100,
                proteinG: (per100[.protein] ?? 0) * grams / 100))
            newFoods.append(food.checked(grams: grams, meal: mealName))
        }

        var dayFoods: [CheckedFood] = []
        for meal in meals {
            for item in meal.items {
                if let f = await data.food(named: item.name) { dayFoods.append(f.checked(grams: item.grams, meal: meal.name)) }
            }
        }
        let report = DietaryConstraintChecker.check(
            foods: dayFoods + newFoods, constraints: data.constraints(),
            allergens: data.profile.allergens, isCompleteDay: false)

        if report.isBlocked {
            return [
                "status": "blocked",
                "reasons": report.violations.filter(\.isBlocking).map(\.message),
                "note": "Nothing was logged. Tell the person why in one sentence.",
            ]
        }

        let action = AssistantPendingAction(
            payload: .logFoods(day: day, meal: mealName, items: proposed),
            title: String(localized: "Add to \(mealName)"),
            lines: proposed.map { String(localized: "\($0.name) – \(DietaryUnits.format($0.grams)) g") },
            report: report)
        enqueue(action)
        return [
            "status": "needs_confirmation",
            "action_id": action.id.uuidString,
            "meal": mealName,
            "date": Self.dayString(day, calendar: calendar),
            "items": proposed.map { ["name": $0.name, "grams": Self.round($0.grams), "kcal": Self.round($0.kcal)] },
            "warnings": report.violations.map(\.message),
            "note": "Shown to the person as a card. Ask them to confirm; do not say it is logged.",
        ]
    }

    func removeLoggedFood(_ args: [String: Any]) async -> [String: Any] {
        let day = parseDay(args["date"])
        let meals = await data.meals(on: day)
        guard let mealName = resolveMeal(args["meal"] as? String, in: meals, day: day),
              let meal = meals.first(where: { $0.name == mealName }) else {
            return ["error": "meal not found"]
        }
        let wanted = (args["food_name"] as? String ?? "").lowercased()
        var name: String?
        if let idString = args["food_id"] as? String, let id = UUID(uuidString: idString), let food = await data.food(id: id) {
            name = meal.items.first { $0.name == food.name }?.name
        }
        if name == nil, !wanted.isEmpty {
            name = meal.items.first { $0.name.lowercased() == wanted }?.name
                ?? meal.items.first { $0.name.lowercased().contains(wanted) }?.name
        }
        guard let foodName = name else {
            return ["error": "that food is not logged in \(mealName)", "logged": meal.items.map(\.name)]
        }
        let action = AssistantPendingAction(
            payload: .removeFood(day: day, meal: mealName, foodName: foodName),
            title: String(localized: "Remove from \(mealName)"),
            lines: [foodName])
        enqueue(action)
        return ["status": "needs_confirmation", "action_id": action.id.uuidString, "meal": mealName, "food": foodName]
    }

    func setDietaryConstraints(_ args: [String: Any]) -> [String: Any] {
        let raw = args["constraints"] as? [[String: Any]] ?? []
        let parsed = raw.compactMap(Self.parseConstraint)
        guard !parsed.isEmpty else {
            return ["error": "no valid constraints; each needs kind and either nutrient+amount+unit or food"]
        }
        let action = AssistantPendingAction(
            payload: .constraints(parsed),
            title: String(localized: "Save dietary constraints"),
            lines: parsed.map { c in
                c.source == .selfReported ? c.summary : "\(c.summary) (\(c.source.displayName))"
            })
        enqueue(action)
        return [
            "status": "needs_confirmation",
            "action_id": action.id.uuidString,
            "constraints": parsed.map(Self.constraintJSON),
            "note": "These are the person's own constraints; the app records them, it does not judge them medically.",
        ]
    }

    private enum NamedKind { case recipe, food }

    private func createNamed(_ args: [String: Any], kind: NamedKind) -> [String: Any] {
        let name = (args["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else { return ["error": "name is required"] }
        let action = AssistantPendingAction(
            payload: kind == .recipe ? .recipe(name: name) : .food(name: name),
            title: kind == .recipe ? String(localized: "Create a recipe") : String(localized: "Create a food"),
            lines: [name])
        enqueue(action)
        return ["status": "needs_confirmation", "action_id": action.id.uuidString, "name": name]
    }

    func createMealPlan(_ args: [String: Any]) -> [String: Any] {
        let days = min(max(Self.int(args["days"]) ?? 1, 1), 7)
        var notes = (args["notes"] as? [String] ?? []).map { String($0.prefix(200)) }
        if let note = args["note"] as? String, !note.isEmpty { notes.append(String(note.prefix(200))) }
        // The app's own generator gets the stored constraints as prompts too.
        notes.append(contentsOf: data.constraints().map(\.summary))
        let action = AssistantPendingAction(
            payload: .mealPlan(days: days, notes: notes),
            title: days == 1 ? String(localized: "Make a day plan") : String(localized: "Make a \(days)-day plan"),
            lines: notes)
        enqueue(action)
        return ["status": "needs_confirmation", "action_id": action.id.uuidString, "days": days,
                "note": "After confirmation the plan is generated in the app's Generate tab and checked against the constraints."]
    }

    func setConstitution(_ args: [String: Any]) -> [String: Any] {
        let raw = args["answers"] as? [String] ?? []
        let answers = raw.compactMap { AyurvedaDosha(rawValue: $0.lowercased()) }
        let count = AyurvedaConstitutionQuestion.all.count
        guard raw.count == count, answers.count == count else {
            return ["error": "answers must be \(count) values, one of vata/pitta/kapha per question in order"]
        }
        let result = AyurvedaConstitutionResult.from(answers: answers)
        let action = AssistantPendingAction(
            payload: .constitution(answers: answers),
            title: String(localized: "Save your constitution"),
            lines: [result.label] + (result.uncertaintyNote.map { [$0] } ?? []))
        enqueue(action)
        return ["status": "needs_confirmation", "action_id": action.id.uuidString, "result": result.label]
    }

    // MARK: - Confirm, discard, undo

    private func enqueue(_ action: AssistantPendingAction) {
        // One pending log per meal and day: a newer proposal replaces the older one.
        if case let .logFoods(day, meal, _) = action.payload {
            pending.removeAll {
                if case let .logFoods(d, m, _) = $0.payload { return d == day && m == meal }
                return false
            }
        }
        pending.append(action)
    }

    /// The person changed the grams on the card (0 removes the food); the
    /// check runs again on the new amounts.
    func updateGrams(actionID: UUID, foodID: UUID, grams: Double) async {
        guard let index = pending.firstIndex(where: { $0.id == actionID }),
              case let .logFoods(day, meal, items) = pending[index].payload,
              let i = items.firstIndex(where: { $0.foodID == foodID }) else { return }
        var updated = items
        if grams <= 0 {
            updated.remove(at: i)
        } else if let food = await data.food(id: foodID) {
            let g = min(grams, 3000)
            updated[i].grams = g
            updated[i].kcal = (food.per100g[.energy] ?? 0) * g / 100
            updated[i].proteinG = (food.per100g[.protein] ?? 0) * g / 100
        }
        guard !updated.isEmpty else { pending.remove(at: index); return }
        let report = await checkLog(day: day, meal: meal, items: updated)
        pending[index].payload = .logFoods(day: day, meal: meal, items: updated)
        pending[index].lines = updated.map { String(localized: "\($0.name) – \(DietaryUnits.format($0.grams)) g") }
        pending[index].report = report
    }

    /// The whole day as it would be, checked against constraints and allergies.
    func checkLog(day: Date, meal: String, items: [AssistantProposedItem]) async -> ConstraintReport {
        var foods: [CheckedFood] = []
        for record in await data.meals(on: day) {
            for item in record.items {
                if let f = await data.food(named: item.name) { foods.append(f.checked(grams: item.grams, meal: record.name)) }
            }
        }
        for item in items {
            if let f = await data.food(id: item.foodID) { foods.append(f.checked(grams: item.grams, meal: meal)) }
        }
        return DietaryConstraintChecker.check(
            foods: foods, constraints: data.constraints(),
            allergens: data.profile.allergens, isCompleteDay: false)
    }

    /// The person unticked one extracted constraint before saving.
    func removeConstraint(actionID: UUID, constraintID: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == actionID }),
              case let .constraints(list) = pending[index].payload else { return }
        let kept = list.filter { $0.id != constraintID }
        if kept.isEmpty { pending.remove(at: index); return }
        pending[index].payload = .constraints(kept)
        pending[index].lines = kept.map { c in c.source == .selfReported ? c.summary : "\(c.summary) (\(c.source.displayName))" }
    }

    func discard(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    func discardAll() {
        pending.removeAll()
    }

    /// Applies a confirmed action. Only actions the app itself queued can be applied.
    func confirm(_ id: UUID) async -> AssistantApplyResult? {
        guard let action = pending.first(where: { $0.id == id }) else { return nil }
        pending.removeAll { $0.id == id }
        switch action.payload {
        case let .logFoods(day, mealName, items):
            let meals = await data.meals(on: day)
            guard var meal = meals.first(where: { $0.name == mealName }) else {
                return .init(message: String(localized: "That meal is no longer in your day."), undo: nil)
            }
            let before = meal
            for item in items {
                if let i = meal.items.firstIndex(where: { $0.name == item.name }) {
                    meal.items[i].grams += item.grams
                } else {
                    meal.items.append(.init(name: item.name, grams: item.grams))
                }
            }
            guard let saved = await data.save(meal, on: day) else {
                return .init(message: String(localized: "The meal could not be saved. Check calendar access in Settings."), undo: nil)
            }
            var restorable = before
            restorable.eventID = saved.eventID
            let undo = AssistantUndo(day: day, before: restorable, message: String(localized: "Added to \(mealName)."))
            lastUndo = undo
            return .init(message: undo.message, undo: undo)

        case let .removeFood(day, mealName, foodName):
            let meals = await data.meals(on: day)
            guard var meal = meals.first(where: { $0.name == mealName }) else {
                return .init(message: String(localized: "That meal is no longer in your day."), undo: nil)
            }
            let before = meal
            meal.items.removeAll { $0.name == foodName }
            _ = await data.save(meal, on: day)
            let undo = AssistantUndo(day: day, before: before, message: String(localized: "Removed from \(mealName)."))
            lastUndo = undo
            return .init(message: undo.message, undo: undo)

        case let .constraints(list):
            data.mergeConstraints(list)
            return .init(message: String(localized: "Saved. You can edit them in Settings → Dietary constraints."), undo: nil)

        case let .constitution(answers):
            data.saveConstitution(answers: answers)
            return .init(message: String(localized: "Your constitution is saved."), undo: nil)

        case let .recipe(name):
            let ok = data.startRecipe(named: name)
            return .init(message: ok ? String(localized: "Creating \(name). It will appear in the Generate tab.")
                                     : String(localized: "The recipe could not be started."), undo: nil)

        case let .food(name):
            let ok = data.startFood(named: name)
            return .init(message: ok ? String(localized: "Creating \(name). It will appear in the Generate tab.")
                                     : String(localized: "The food could not be started."), undo: nil)

        case let .mealPlan(days, notes):
            let ok = data.startMealPlan(days: days, notes: notes)
            return .init(message: ok ? String(localized: "Your plan is being made. It will appear in the Generate tab.")
                                     : String(localized: "The plan could not be started."), undo: nil)
        }
    }

    /// Puts the meal back exactly as it was before the last confirmed log.
    func undo(_ undo: AssistantUndo) async -> Bool {
        let ok = await data.save(undo.before, on: undo.day) != nil
        if ok, lastUndo == undo { lastUndo = nil }
        return ok
    }

    // MARK: - Allergy

    private func allergenHit(_ food: CompactFoodItem) -> String? {
        let expanded = Allergen.expanded(from: Set(data.profile.allergens))
        return expanded.sorted { $0.rawValue < $1.rawValue }
            .first { food.contains(allergen: $0.rawValue) }?.displayName
    }

    // MARK: - Days and meals

    /// "today", "yesterday", "tomorrow" or "YYYY-MM-DD"; anything else is today.
    func parseDay(_ value: Any?) -> Date {
        let today = calendar.startOfDay(for: now())
        guard let text = (value as? String)?.lowercased().trimmingCharacters(in: .whitespaces), !text.isEmpty else { return today }
        switch text {
        case "today": return today
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        default:
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = calendar.timeZone
            f.dateFormat = "yyyy-MM-dd"
            guard let d = f.date(from: text) else { return today }
            // Logging is for recent days only.
            let distance = abs(calendar.dateComponents([.day], from: today, to: d).day ?? 0)
            return distance <= 31 ? calendar.startOfDay(for: d) : today
        }
    }

    /// Finds the profile meal the person means: its own name, a common word for
    /// it in English or Bulgarian, or the meal closest to now.
    func resolveMeal(_ requested: String?, in meals: [AssistantMealRecord], day: Date) -> String? {
        guard !meals.isEmpty else { return nil }
        let ordered = meals.sorted { $0.start < $1.start }
        let text = (requested ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            if let exact = ordered.first(where: { $0.name.lowercased() == text }) { return exact.name }
            if let localized = ordered.first(where: {
                String(localized: String.LocalizationValue($0.name)).lowercased() == text
            }) { return localized.name }
            if let named = ordered.first(where: { $0.name.lowercased().contains(text) || text.contains($0.name.lowercased()) }) {
                return named.name
            }
            let breakfast = ["breakfast", "закуска", "morning", "сутрин"]
            let lunch = ["lunch", "обяд", "noon", "midday"]
            let dinner = ["dinner", "supper", "вечеря", "evening", "вечер"]
            if breakfast.contains(where: { text.contains($0) }) { return ordered.first?.name }
            if dinner.contains(where: { text.contains($0) }) { return ordered.last?.name }
            if lunch.contains(where: { text.contains($0) }) { return closest(to: 13, in: ordered, day: day)?.name }
        }
        let hour = calendar.isDate(day, inSameDayAs: now())
            ? Double(calendar.component(.hour, from: now())) + Double(calendar.component(.minute, from: now())) / 60
            : 13
        return closest(to: hour, in: ordered, day: day)?.name
    }

    private func closest(to hour: Double, in meals: [AssistantMealRecord], day: Date) -> AssistantMealRecord? {
        meals.min { a, b in
            abs(hourOf(a.start) - hour) < abs(hourOf(b.start) - hour)
        }
    }

    private func hourOf(_ date: Date) -> Double {
        Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
    }

    // MARK: - JSON helpers

    static func parseConstraint(_ raw: [String: Any]) -> DietaryConstraint? {
        guard let kindText = raw["kind"] as? String else { return nil }
        let kind: DietaryConstraint.Kind
        switch kindText {
        case "nutrient_max", "nutrientMax", "max", "limit": kind = .nutrientMax
        case "nutrient_min", "nutrientMin", "min", "target": kind = .nutrientMin
        case "exclude_food", "excludeFood", "exclude": kind = .excludeFood
        case "prefer_food", "preferFood", "prefer": kind = .preferFood
        default: return nil
        }
        let sourceText = (raw["source"] as? String ?? "self").lowercased()
        let source: DietaryConstraint.Source = switch sourceText {
        case "doctor": .doctor
        case "prescription": .prescription
        case "lab_report", "labreport", "lab": .labReport
        default: .selfReported
        }
        let period: DietaryConstraint.Period = (raw["period"] as? String) == "meal" ? .meal : .day
        let note = (raw["note"] as? String).map { String($0.prefix(300)) }
        let c = DietaryConstraint(
            kind: kind,
            nutrient: raw["nutrient"] as? String,
            amount: double(raw["amount"]),
            unit: (raw["unit"] as? String).map(DietaryUnits.normalized),
            period: period,
            foodTerm: (raw["food"] as? String).map { String($0.prefix(60)) },
            source: source,
            note: note)
        return c.isValid ? c : nil
    }

    static func constraintJSON(_ c: DietaryConstraint) -> [String: Any] {
        var r: [String: Any] = ["id": c.id.uuidString, "kind": c.kind.rawValue, "period": c.period.rawValue,
                                "source": c.source.rawValue, "summary": c.summary]
        if let n = c.nutrient { r["nutrient"] = n }
        if let a = c.amount { r["amount"] = a }
        if let u = c.unit { r["unit"] = u }
        if let f = c.foodTerm { r["food"] = f }
        if let n = c.note { r["note"] = n }
        return r
    }

    static func foodJSON(_ food: CompactFoodItem) -> [String: Any] {
        let p = food.per100g
        var row: [String: Any] = [
            "food_id": food.id.uuidString,
            "name": food.displayNameForAssistant,
            "per_100g": [
                "kcal": round(p[.energy] ?? 0),
                "protein_g": round(p[.protein] ?? 0),
                "fat_g": round(p[.totalFat] ?? 0),
                "carbs_g": round(p[.carbs] ?? 0),
                "fiber_g": round(p[.fiber] ?? 0),
                "sugar_g": round(p[.totalSugar] ?? 0),
                "sodium_mg": round(p[.sodium] ?? 0),
            ],
        ]
        if food.isRecipe { row["recipe"] = true }
        if let a = food.ayurvedaMetadata {
            var ay: [String: Any] = ["vata": a.doshaVata, "pitta": a.doshaPitta, "kapha": a.doshaKapha, "rasa": a.rasa]
            if let v = a.virya { ay["virya"] = v }
            if a.isInferred { ay["estimated"] = true }
            row["ayurveda"] = ay
        }
        return row
    }

    static func totalsJSON(_ totals: [NutrientType: Double]) -> [String: Any] {
        [
            "kcal": round(totals[.energy] ?? 0),
            "protein_g": round(totals[.protein] ?? 0),
            "fat_g": round(totals[.totalFat] ?? 0),
            "carbs_g": round(totals[.carbs] ?? 0),
            "fiber_g": round(totals[.fiber] ?? 0),
            "sodium_mg": round(totals[.sodium] ?? 0),
        ]
    }

    static func dayString(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func round(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return "{\"error\":\"internal\"}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension CompactFoodItem {
    /// The localized name when the app shows localized food names, else the catalogue name.
    var displayNameForAssistant: String {
        FoodNameLocalizer.active?.localizedName(name) ?? name
    }
}
