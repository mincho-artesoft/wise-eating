import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The free engine. Apple's on-device model is small, so it does not run an
/// open tool loop: it reads the request into one structured step, and the
/// engine runs that step through the same tools the OpenAI engine calls.
/// Without Apple Intelligence a deterministic reader handles the common cases.
@MainActor
final class OnDeviceEngine: AssistantEngine {
    let kind: AssistantEngineKind = .onDevice
    let canReadImages = false

    /// Tests and devices without Apple Intelligence use the deterministic path.
    var useModel: Bool = GlobalState.isAppleIntelligenceAvailable

    struct Step: Equatable, Sendable {
        enum Intent: String, Sendable, CaseIterable {
            case logFood = "log_food"
            case whatDidIEat = "what_did_i_eat"
            case removeFood = "remove_food"
            case setConstraint = "set_constraint"
            case createRecipe = "create_recipe"
            case createFood = "create_food"
            case mealPlan = "meal_plan"
            case findPractice = "find_practice"
            case findPose = "find_pose"
            case offTopic = "off_topic"
            case medicalAdvice = "medical_advice"
            case help
        }

        struct Food: Equatable, Sendable {
            var name: String
            var grams: Double
        }

        var intent: Intent
        var meal: String?
        var date: String?
        var foods: [Food] = []
        var name: String?
        var days: Int?
        var constraints: [DietaryConstraint] = []
    }

    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) async throws -> AssistantReply {
        if turn.imageJPEG != nil { throw AssistantEngineError.imagesNeedOpenAI }
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return AssistantReply(text: AssistantInstructions.helpReply) }

        // Scope is decided before any model runs, so a jailbreak in the text
        // cannot widen it.
        switch AssistantScope.classify(text) {
        case .offTopic: return AssistantReply(text: AssistantInstructions.offTopicReply)
        case .medical: return AssistantReply(text: AssistantInstructions.medicalReply)
        case .inScope: break
        }

        var step = Self.deterministicStep(for: text)
        #if canImport(FoundationModels)
        if useModel, #available(iOS 26.0, *), step.intent == .help || step.intent == .logFood {
            if let modelStep = try? await Self.modelStep(for: text) {
                step = Self.merge(model: modelStep, deterministic: step)
            }
        }
        #endif
        return await run(step, toolbox: toolbox)
    }

    // MARK: - Running a step through the tools

    func run(_ step: Step, toolbox: AssistantToolbox) async -> AssistantReply {
        switch step.intent {
        case .offTopic:
            return .init(text: AssistantInstructions.offTopicReply)
        case .medicalAdvice:
            return .init(text: AssistantInstructions.medicalReply)
        case .help:
            return .init(text: AssistantInstructions.helpReply)

        case .whatDidIEat:
            let day = Self.object(await toolbox.call("get_day", arguments: Self.args(["date": step.date ?? "today"])))
            return .init(text: Self.describeDay(day))

        case .logFood:
            guard !step.foods.isEmpty else { return .init(text: AssistantInstructions.helpReply) }
            var items: [[String: Any]] = []
            var missing: [String] = []
            var allergyNotes: [String] = []
            for food in step.foods {
                let found = Self.object(await toolbox.call("search_foods", arguments: Self.args(["query": food.name, "limit": 3])))
                let results = found["results"] as? [[String: Any]] ?? []
                // A single ingredient ("eggs") is the plain food, not the first dish that has it.
                // Foods without any nutrient data come last: they would log as zero.
                let usable = results.filter { $0["avoided"] == nil }
                let measured = usable.filter { Self.kcalPer100(of: $0) > 0 }
                if let first = measured.first(where: { $0["recipe"] == nil }) ?? measured.first
                    ?? usable.first(where: { $0["recipe"] == nil }) ?? usable.first ?? results.first,
                   let id = first["food_id"] as? String {
                    items.append(["food_id": id, "grams": food.grams])
                } else {
                    missing.append(food.name)
                    // Was it left out because of an allergy?
                    let all = Self.object(await toolbox.call("search_foods", arguments: Self.args([
                        "query": food.name, "limit": 1, "filters": ["exclude_allergens": false],
                    ])))
                    if let hit = (all["results"] as? [[String: Any]])?.first, let allergy = hit["allergy"] as? String {
                        allergyNotes.append(String(localized: "\(food.name) was left out: it contains \(allergy), which is in your allergies."))
                    }
                }
            }
            guard !items.isEmpty else {
                let notFound = String(localized: "I could not find \(missing.joined(separator: ", ")) in the catalogue.")
                return .init(text: ([notFound] + allergyNotes).joined(separator: " "))
            }
            var logArgs: [String: Any] = ["items": items, "date": step.date ?? "today"]
            if let meal = step.meal { logArgs["meal"] = meal }
            let result = Self.object(await toolbox.call("log_food", arguments: Self.args(logArgs)))
            var lines: [String] = []
            switch result["status"] as? String {
            case "needs_confirmation":
                let meal = result["meal"] as? String ?? ""
                lines.append(String(localized: "Here is what I found for \(meal). Check the grams and confirm."))
                lines.append(contentsOf: result["warnings"] as? [String] ?? [])
            case "blocked":
                lines.append(contentsOf: result["reasons"] as? [String] ?? [])
            default:
                lines.append(result["error"] as? String ?? String(localized: "Something went wrong."))
            }
            if !missing.isEmpty {
                lines.append(String(localized: "Not found: \(missing.joined(separator: ", "))."))
            }
            lines.append(contentsOf: allergyNotes)
            return .init(text: lines.joined(separator: " "))

        case .removeFood:
            var a: [String: Any] = ["food_name": step.name ?? step.foods.first?.name ?? "", "date": step.date ?? "today"]
            if let meal = step.meal { a["meal"] = meal }
            let result = Self.object(await toolbox.call("remove_logged_food", arguments: Self.args(a)))
            if result["status"] as? String == "needs_confirmation" {
                return .init(text: String(localized: "Confirm to remove it."))
            }
            return .init(text: result["error"] as? String ?? String(localized: "Something went wrong."))

        case .setConstraint:
            guard !step.constraints.isEmpty else {
                return .init(text: String(localized: "Tell me the limit with an amount, for example \"protein at most 20 g a day\", or a food to leave out."))
            }
            let raw = step.constraints.map { c -> [String: Any] in
                var r: [String: Any] = ["kind": Self.kindName(c.kind), "period": c.period.rawValue, "source": c.source.rawValue]
                if let n = c.nutrient { r["nutrient"] = n }
                if let a = c.amount { r["amount"] = a }
                if let u = c.unit { r["unit"] = u }
                if let f = c.foodTerm { r["food"] = f }
                return r
            }
            let result = Self.object(await toolbox.call("set_dietary_constraints", arguments: Self.args(["constraints": raw])))
            if result["status"] as? String == "needs_confirmation" {
                return .init(text: String(localized: "I will record this as your own constraint and check your meals against it. Confirm to save."))
            }
            return .init(text: result["error"] as? String ?? String(localized: "Something went wrong."))

        case .createRecipe, .createFood:
            let tool = step.intent == .createRecipe ? "create_recipe" : "create_food"
            let result = Self.object(await toolbox.call(tool, arguments: Self.args(["name": step.name ?? ""])))
            return .init(text: result["status"] as? String == "needs_confirmation"
                ? String(localized: "Confirm and the app will create it.")
                : (result["error"] as? String ?? String(localized: "Tell me the name of the dish.")))

        case .mealPlan:
            let result = Self.object(await toolbox.call("create_meal_plan", arguments: Self.args(["days": step.days ?? 1])))
            return .init(text: result["status"] as? String == "needs_confirmation"
                ? String(localized: "Confirm and the app will make the plan, checked against your constraints and allergies.")
                : (result["error"] as? String ?? String(localized: "Something went wrong.")))

        case .findPractice, .findPose:
            let tool = step.intent == .findPractice ? "find_practice" : "find_pose"
            let result = Self.object(await toolbox.call(tool, arguments: Self.args(["query": step.name ?? "", "limit": 3])))
            let rows = result["results"] as? [[String: Any]] ?? []
            guard !rows.isEmpty else { return .init(text: String(localized: "I did not find a match in the app.")) }
            let names = rows.compactMap { ($0["title"] as? String) ?? ($0["name"] as? String) }
            return .init(text: String(localized: "In the app: \(names.joined(separator: ", ")).") )
        }
    }

    // MARK: - Deterministic reading

    static func deterministicStep(for text: String) -> Step {
        let lower = text.lowercased()
        let constraints = AssistantConstraintParser.parse(text)
        if !constraints.isEmpty { return Step(intent: .setConstraint, constraints: constraints) }
        if ["more protein", "повече протеин", "повече белтък"].contains(where: { lower.contains($0) }) {
            return Step(intent: .setConstraint)
        }

        switch AssistantFoodLogParser.intent(of: text) {
        case .whatDidIEat:
            let parsed = AssistantFoodLogParser.parse(text)
            return Step(intent: .whatDidIEat, date: parsed.date)
        case .log:
            let parsed = AssistantFoodLogParser.parse(text)
            return Step(
                intent: .logFood, meal: parsed.meal, date: parsed.date,
                foods: parsed.items.map { .init(name: $0.query, grams: AssistantPortions.grams(for: $0)) })
        case .unknown:
            break
        }

        let markers: [(Step.Intent, [String])] = [
            (.mealPlan, ["meal plan", "day plan", "plan for", "plan my", "make a plan", "план за", "хранителен режим", "направи план", "режим за"]),
            (.createRecipe, ["recipe", "рецепта"]),
            (.findPose, ["pose", "asana", "поза", "асана"]),
            (.findPractice, ["practice", "breathing", "meditation", "pranayama", "практика", "дишане", "медитация"]),
        ]
        for (intent, words) in markers where words.contains(where: { lower.contains($0) }) {
            var step = Step(intent: intent, name: text)
            if intent == .mealPlan {
                step.days = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? 1
            }
            return step
        }
        return Step(intent: .help)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    static func modelStep(for text: String) async throws -> Step {
        let session = LanguageModelSession(instructions: Instructions { AssistantInstructions.system })
        let response = try await session.respond(
            to: "Read this request into one step. Request: \(text)",
            generating: OnDeviceAssistantModelStep.self,
            options: GenerationOptions(sampling: .greedy))
        let c = response.content
        return Step(
            intent: Step.Intent(rawValue: c.intent) ?? .help,
            meal: c.meal.isEmpty ? nil : c.meal,
            date: c.date.isEmpty ? nil : c.date,
            foods: c.foods.map { .init(name: $0.name, grams: $0.grams) })
    }
    #endif

    /// The model reads foods and grams better; scope and constraints stay deterministic.
    static func merge(model: Step, deterministic: Step) -> Step {
        guard model.intent == .logFood || model.intent == .whatDidIEat else { return deterministic }
        var step = model
        step.meal = model.meal ?? deterministic.meal
        step.date = model.date ?? deterministic.date
        if step.intent == .logFood, step.foods.isEmpty { step.foods = deterministic.foods }
        return step
    }

    // MARK: - Helpers

    static func describeDay(_ day: [String: Any]) -> String {
        let meals = day["meals"] as? [[String: Any]] ?? []
        var parts: [String] = []
        for meal in meals {
            let items = meal["items"] as? [[String: Any]] ?? []
            guard !items.isEmpty, let name = meal["meal"] as? String else { continue }
            let list = items.compactMap { i -> String? in
                guard let n = i["name"] as? String else { return nil }
                return "\(n) \(DietaryUnits.format(AssistantToolbox.double(i["grams"]) ?? 0)) g"
            }
            parts.append("\(name): \(list.joined(separator: ", "))")
        }
        guard !parts.isEmpty else { return String(localized: "Nothing is logged for that day yet.") }
        let totals = day["totals"] as? [String: Any] ?? [:]
        let kcal = DietaryUnits.format(AssistantToolbox.double(totals["kcal"]) ?? 0)
        let protein = DietaryUnits.format(AssistantToolbox.double(totals["protein_g"]) ?? 0)
        var text = parts.joined(separator: ". ") + ". "
        text += String(localized: "In total about \(kcal) kcal and \(protein) g of protein.")
        let warnings = day["warnings"] as? [String] ?? []
        if !warnings.isEmpty { text += " " + warnings.joined(separator: " ") }
        return text
    }

    static func kcalPer100(of row: [String: Any]) -> Double {
        AssistantToolbox.double((row["per_100g"] as? [String: Any])?["kcal"]) ?? 0
    }

    static func kindName(_ kind: DietaryConstraint.Kind) -> String {
        switch kind {
        case .nutrientMax: "nutrient_max"
        case .nutrientMin: "nutrient_min"
        case .excludeFood: "exclude_food"
        case .preferFood: "prefer_food"
        }
    }

    static func args(_ object: [String: Any]) -> String { AssistantToolbox.json(object) }

    static func object(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct OnDeviceAssistantModelFood {
    @Guide(description: "A short generic food name in English as a food catalogue would list it, e.g. 'egg', 'bread, whole wheat', 'butter'.")
    var name: String
    @Guide(description: "Realistic grams eaten for what the person said, e.g. two eggs = 100, one slice of bread = 30, butter on bread = 10.", .range(1...2000))
    var grams: Double
}

@available(iOS 26.0, *)
@Generable
struct OnDeviceAssistantModelStep {
    @Guide(description: "What the person wants.", .anyOf(["log_food", "what_did_i_eat", "remove_food", "set_constraint", "create_recipe", "create_food", "meal_plan", "find_practice", "find_pose", "off_topic", "medical_advice", "help"]))
    var intent: String
    @Guide(description: "The meal: breakfast, lunch, dinner, snack, or empty if not said.")
    var meal: String
    @Guide(description: "today, yesterday, or empty.")
    var date: String
    @Guide(description: "Each food the person says they ate, one entry per food.")
    var foods: [OnDeviceAssistantModelFood]
}
#endif
