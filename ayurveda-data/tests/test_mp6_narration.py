import gzip
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MEAL_PLANNING = ROOT / "Ayura" / "AI" / "MealPlanning"
NARRATION = MEAL_PLANNING / "MealPlanNarration.swift"
FOUNDATION_MODELS_NARRATOR = (
    MEAL_PLANNING / "MealPlanNarrator+FoundationModels.swift"
)
REQUEST = MEAL_PLANNING / "MealPlanRequest.swift"
TELEMETRY = MEAL_PLANNING / "PlannerTelemetry.swift"
PLANNER = MEAL_PLANNING / "USDAWeeklyMealPlanner.swift"
MODELS = MEAL_PLANNING / "AIMealPlanModels.swift"
SOLVER = MEAL_PLANNING / "DeterministicMealPlanSolver.swift"
AYURVEDA_SEED = ROOT / "Ayura" / "ayurveda_seed.json.gz"
FOODS = ROOT / "Ayura" / "Legacy" / "foods.json"
FOOD_CONCEPTS = ROOT / "Ayura" / "food_concepts.json.gz"
FOOD_ROLES = ROOT / "Ayura" / "food_roles.json.gz"
AYURVEDA_RULES = ROOT / "Ayura" / "ayurveda_rules.json"


PURE_HARNESS = r'''
import Foundation

actor CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

func facts(days: Int) -> [MP6NarrationFact] {
    let meals = [
        (
            "Breakfast",
            ["Oat porridge", "Stewed apple"],
            412.0,
            15.4,
            ["sweet", "astringent"],
            "warming"
        ),
        (
            "Lunch",
            ["Mung dal kitchari", "Cucumber raita"],
            638.0,
            25.8,
            ["sweet", "salty", "astringent"],
            "mixed"
        ),
        (
            "Dinner",
            ["Pumpkin soup", "Whole-wheat flatbread"],
            521.0,
            19.6,
            ["sweet"],
            "cooling"
        ),
    ]
    return (1...days).flatMap { day in
        meals.enumerated().map { index, meal in
            MP6NarrationFact(
                day: day,
                slotIndex: index,
                slotName: meal.0,
                dishNames: meal.1,
                kcal: meal.2 + Double(day - 1) * 7,
                proteinGrams: meal.3,
                tastes: meal.4,
                thermalCharacter: meal.5,
                agni: day == 2 ? "slow" : "balanced"
            )
        }
    }
}

@main
struct MP6PureHarness {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            fatalError("scenario required")
        }

        switch CommandLine.arguments[1] {
        case "template3":
            let titles = MP6TemplateNarrator.narrate(facts(days: 3))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(
                String(
                    data: try encoder.encode(titles),
                    encoding: .utf8
                )!
            )

        case "mismatch":
            let supplied = facts(days: 3)
            let counter = CallCounter()
            let outcome = await MP6NarrationCoordinator.narrate(
                facts: supplied,
                modelAvailable: true,
                modelResponse: { modelFacts in
                    await counter.increment()
                    return MP6TemplateNarrator.narrate(
                        Array(modelFacts.dropLast())
                    )
                }
            )
            print(
                "MP6-MISMATCH calls=\(await counter.value()) "
                    + "fallback=\(outcome.usedTemplate) "
                    + "count=\(outcome.titles.count) "
                    + "reason=\(outcome.fallbackReason ?? "none")"
            )

        case "determinism":
            let supplied = facts(days: 7)
            let first = MP6TemplateNarrator.narrate(supplied)
            let identical = (0..<100).allSatisfy { _ in
                MP6TemplateNarrator.narrate(supplied) == first
            }
            print(identical ? "PASS determinism" : "FAIL determinism")

        case "frames7":
            print(
                facts(days: 7)
                    .map { MP6TemplateNarrator.frameIndex(for: $0) }
                    .map(String.init)
                    .joined(separator: ",")
            )

        case "timeout":
            let supplied = facts(days: 1)
            let outcome = await MP6NarrationCoordinator.narrate(
                facts: supplied,
                modelAvailable: true,
                wallClockBudgetNanoseconds: 1_000_000,
                modelResponse: { modelFacts in
                    try await Task.sleep(nanoseconds: 250_000_000)
                    return MP6TemplateNarrator.narrate(modelFacts)
                }
            )
            print(
                "MP6-TIMEOUT fallback=\(outcome.usedTemplate) "
                    + "count=\(outcome.titles.count) "
                    + "reason=\(outcome.fallbackReason ?? "none")"
            )

        default:
            fatalError("unknown scenario")
        }
    }
}
'''


TELEMETRY_HARNESS = r'''
import Foundation

actor MP6CallCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

func telemetryFacts(days: Int) -> [MP6NarrationFact] {
    (1...days).flatMap { day in
        (0..<3).map { slot in
            MP6NarrationFact(
                day: day,
                slotIndex: slot,
                slotName: ["Breakfast", "Lunch", "Dinner"][slot],
                dishNames: ["Resolved dish \(day)-\(slot)"],
                kcal: 500,
                proteinGrams: 20,
                tastes: ["sweet"],
                thermalCharacter: "neutral",
                agni: "balanced"
            )
        }
    }
}

@main
struct MP6TelemetryHarness {
    @MainActor
    static func main() async {
        guard CommandLine.arguments.count >= 3,
              let dayCount = Int(CommandLine.arguments[2]) else {
            fatalError("scenario and day count required")
        }
        let counter = MP6CallCounter()
        await PlannerTelemetry.shared.reset(
            label: "mp6-\(CommandLine.arguments[1])-\(dayCount)"
        )

        if CommandLine.arguments[1] == "endtoend" {
            await PlannerTelemetry.shared.beginStage("interpretation")
            _ = await MealPlanIntentCoordinator.parse(
                prompts: (1...dayCount).map { "day \($0)" },
                modelAvailable: true,
                modelResponse: { _ in
                    await counter.increment()
                    await PlannerTelemetry.shared.noteSession(
                        site: "mealPlanIntentParse"
                    )
                    var request = ParsedRequest()
                    request.days = dayCount
                    return request
                },
                onModelCall: { ok, elapsed in
                    await PlannerTelemetry.shared.noteRespond(
                        site: "mealPlanIntentParse",
                        ok: ok,
                        ms: elapsed
                    )
                }
            )
            await PlannerTelemetry.shared.endStage("interpretation")
        }

        await PlannerTelemetry.shared.beginStage("narration")
        let facts = telemetryFacts(days: dayCount)
        let outcome = await MP6NarrationCoordinator.narrate(
            facts: facts,
            modelAvailable: true,
            modelResponse: { modelFacts in
                await counter.increment()
                await PlannerTelemetry.shared.noteSession(
                    site: "mealPlanNarration"
                )
                await PlannerTelemetry.shared.noteRespond(
                    site: "mealPlanNarration",
                    ok: true,
                    ms: 1
                )
                return MP6TemplateNarrator.narrate(modelFacts)
            }
        )
        await PlannerTelemetry.shared.endStage("narration")
        print(await PlannerTelemetry.shared.summary())
        print(
            "MP6-CALL-GATE scenario=\(CommandLine.arguments[1]) "
                + "days=\(dayCount) closureCalls=\(await counter.value()) "
                + "titles=\(outcome.titles.count)"
        )
    }
}
'''

REAL_SOLVER_HARNESS = r'''
import Foundation

private struct RealCandidate: Codable {
    let candidate: MP5Candidate
    let thermalCharacter: String
}

private struct RealMealEvidence: Codable {
    let day: Int
    let slotIndex: Int
    let frameIndex: Int
    let componentIDs: [Int]
    let title: String
}

private struct RealSampleOutput: Codable {
    let candidateSource: String
    let sourceCandidateCount: Int
    let twoDayNoRepeat: Bool
    let distinctFoodCount: Int
    let meals: [RealMealEvidence]
}

@main
private enum MP6RealSolverHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("candidate JSON path required")
        }
        let wrappers = try JSONDecoder().decode(
            [RealCandidate].self,
            from: Data(contentsOf: URL(
                fileURLWithPath: CommandLine.arguments[1]
            ))
        )
        let candidates = wrappers.map(\.candidate)
        let thermalByID = Dictionary(
            uniqueKeysWithValues: wrappers.map {
                ($0.candidate.id, $0.thermalCharacter)
            }
        )
        let profile = MP5SolverProfile(
            dailyKcal: 2_000,
            dailyProteinTarget: 80,
            ageInMonths: 360,
            allergenConcepts: [],
            excludedFoodIDs: [],
            dosha: nil,
            agni: .balanced,
            season: "varsha",
            enableAyurvedicScoring: false
        )
        let slots = (1...7).flatMap { day in
            ["Breakfast", "Lunch", "Dinner"].map {
                MP5MealSlot(day: day, name: $0)
            }
        }
        let request = MP5SolverRequest(
            profile: profile,
            slots: slots,
            seed: 0x4D50_3662,
            localSearchIterations: 96
        )
        let plan = try DeterministicMealPlanSolver(
            candidates: candidates
        ).solve(request)
        let facts = plan.days.flatMap { day in
            day.meals.enumerated().map { slotIndex, meal in
                let thermalValues = Set(
                    meal.components.compactMap {
                        thermalByID[$0.foodID]
                    }.filter { $0 != "unrecorded" }
                )
                let thermal: String
                if thermalValues.isEmpty {
                    thermal = "unrecorded"
                } else if thermalValues.count == 1 {
                    thermal = thermalValues.first ?? "unrecorded"
                } else {
                    thermal = "mixed"
                }
                return MP6NarrationFact(
                    day: day.day,
                    slotIndex: slotIndex,
                    slotName: meal.name,
                    dishNames: meal.components.map(\.name),
                    kcal: meal.kcal,
                    proteinGrams: meal.protein,
                    tastes: Set(
                        meal.components.flatMap(\.rasa)
                    ).sorted(),
                    thermalCharacter: thermal,
                    agni: profile.agni.rawValue
                )
            }
        }
        let titles = MP6TemplateNarrator.narrate(facts)
        let titleByKey = Dictionary(
            uniqueKeysWithValues: titles.map { ($0.key, $0.title) }
        )
        let mealByKey = Dictionary(
            uniqueKeysWithValues: plan.days.flatMap { day in
                day.meals.enumerated().map {
                    (
                        MP6NarrationKey(
                            day: day.day,
                            slotIndex: $0.offset
                        ),
                        $0.element
                    )
                }
            }
        )
        let evidence = facts.map { fact in
            RealMealEvidence(
                day: fact.day,
                slotIndex: fact.slotIndex,
                frameIndex: MP6TemplateNarrator.frameIndex(for: fact),
                componentIDs: mealByKey[fact.key]?.components.map(\.foodID)
                    ?? [],
                title: titleByKey[fact.key] ?? ""
            )
        }
        let sortedDays = plan.days.sorted { $0.day < $1.day }
        var twoDayNoRepeat = true
        for index in sortedDays.indices {
            let start = max(0, index - request.noRepeatDays)
            let prior = Set(
                sortedDays[start..<index]
                    .flatMap(\.meals)
                    .flatMap(\.components)
                    .map(\.foodID)
            )
            let current = sortedDays[index]
                .meals
                .flatMap(\.components)
                .map(\.foodID)
            twoDayNoRepeat = twoDayNoRepeat
                && prior.isDisjoint(with: current)
                && Set(current).count == current.count
        }
        let output = RealSampleOutput(
            candidateSource: "shipped foods.json + ayurveda_seed.json.gz",
            sourceCandidateCount: candidates.count,
            twoDayNoRepeat: twoDayNoRepeat,
            distinctFoodCount: Set(plan.components.map(\.foodID)).count,
            meals: evidence
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
'''


def normalized_tokens(value):
    return re.findall(r"[a-z0-9]+", value.lower())


def normalized_term(value):
    return re.sub(r"[_-]+", " ", (value or "").strip().lower())


def contains_phrase(tokens, phrase):
    phrase_tokens = normalized_tokens(phrase)
    width = len(phrase_tokens)
    return any(
        tokens[index : index + width] == phrase_tokens
        for index in range(len(tokens) - width + 1)
    )


def safety_concepts(allergens):
    concepts = set()
    for allergen in allergens or []:
        lower = allergen.lower()
        if "milk" in lower:
            concepts.add("dairy")
        if "egg" in lower:
            concepts.add("egg")
        if "cereals containing gluten" in lower:
            concepts.add("gluten")
        if "soy" in lower:
            concepts.add("soy")
        if "sesame" in lower:
            concepts.add("sesame")
        if "peanut" in lower:
            concepts.add("peanut")
        if lower == "nuts" or lower.startswith("nuts ("):
            concepts.add("tree_nuts")
        if "fish" in lower:
            concepts.add("fish")
        if "crustacean" in lower:
            concepts.update(("crustacean", "shellfish"))
        if "mollusc" in lower:
            concepts.update(("mollusc", "shellfish"))
    return concepts


def nutrient_value(food, section, key):
    value = ((food.get(section) or {}).get(key) or {}).get("value")
    return float(value) if value is not None else 0.0


def profile_heaviness(gunas, digestibility):
    if digestibility is not None:
        return min(1, max(0, (5 - float(digestibility)) / 4))
    normalized = {normalized_term(value) for value in gunas or []}
    if normalized.intersection(("guru", "heavy")):
        return 0.85
    if normalized.intersection(("laghu", "light")):
        return 0.2
    return 0.5


def normalize_thermal(value):
    term = normalized_term(value)
    if term in ("heating", "hot", "ushna"):
        return "heating"
    if term in ("cooling", "cold", "sheeta", "shita"):
        return "cooling"
    if term in ("neutral", "balanced"):
        return "neutral"
    return term or "unrecorded"


def make_real_candidate_file(destination):
    with gzip.open(AYURVEDA_SEED, "rt", encoding="utf-8") as source:
        seed = json.load(source)
    with FOODS.open(encoding="utf-8") as source:
        foods = json.load(source)
    with gzip.open(FOOD_CONCEPTS, "rt", encoding="utf-8") as source:
        concept_payload = json.load(source)
    with gzip.open(FOOD_ROLES, "rt", encoding="utf-8") as source:
        role_payload = json.load(source)
    with AYURVEDA_RULES.open(encoding="utf-8") as source:
        rule_payload = json.load(source)

    concepts_by_id = {}
    for concept, food_ids in concept_payload["membership"].items():
        for food_id in food_ids:
            concepts_by_id.setdefault(int(food_id), set()).add(concept)
    role_by_id = {
        int(item["foodId"]): item for item in role_payload["items"]
    }
    role_definitions = {
        item["id"]: item for item in role_payload["definitions"]
    }
    dravya_by_id = {item["id"]: item for item in seed["dravyas"]}
    direct_by_food_id = {
        int(item["foodId"]): item
        for item in seed["dravyas"]
        if item.get("foodId") is not None
    }
    link_by_food_id = {
        int(link["fdcId"]): link
        for link in seed["links"]
    }
    category_rules = {
        item["category"]: item for item in rule_payload["categories"]
    }
    default_rule = rule_payload["default"]
    wrappers = []

    def resolution(food_id, name, categories):
        direct = direct_by_food_id.get(food_id)
        link = link_by_food_id.get(food_id)
        profile = direct or (
            dravya_by_id.get(link["dravyaId"]) if link else None
        )
        if profile:
            dosha = profile.get("dosha") or {}
            tier = "classical"
            if not direct and link and link.get("tier") == "derived":
                tier = "derived"
            return {
                "doshaVata": int(dosha.get("vata", 0)),
                "doshaPitta": int(dosha.get("pitta", 0)),
                "doshaKapha": int(dosha.get("kapha", 0)),
                "rasa": sorted(
                    {
                        normalized_term(value)
                        for value in profile.get("rasa") or []
                    }
                ),
                "hasVipaka": bool(profile.get("vipaka")),
                "hasVirya": bool(profile.get("virya")),
                "hasPrabhava": bool(profile.get("prabhava")),
                "heaviness": profile_heaviness(
                    profile.get("gunas"),
                    profile.get("digestibility"),
                ),
                "seasons": sorted(
                    {
                        normalized_term(value)
                        for value in profile.get("seasons") or []
                    }
                ),
                "tier": tier,
                "thermal": normalize_thermal(profile.get("virya")),
                "engineExcluded": bool(profile.get("engineExcluded")),
            }

        category = categories[0] if categories else ""
        rule = category_rules.get(category, default_rule)
        name_tokens = normalized_tokens(name)
        modifier_gunas = []
        modifier_vpk = [0, 0, 0]
        for modifier in rule_payload["modifiers"]:
            if any(
                contains_phrase(name_tokens, phrase)
                for phrase in modifier["phrases"]
            ):
                modifier_gunas.extend(modifier.get("gunas") or [])
                modifier_vpk = [
                    modifier_vpk[index] + modifier["vpk"][index]
                    for index in range(3)
                ]
        vpk = [
            min(2, max(-2, rule["vpk"][index] + modifier_vpk[index]))
            for index in range(3)
        ]
        return {
            "doshaVata": vpk[0],
            "doshaPitta": vpk[1],
            "doshaKapha": vpk[2],
            "rasa": [],
            "hasVipaka": False,
            "hasVirya": bool(rule.get("virya")),
            "hasPrabhava": False,
            "heaviness": profile_heaviness(
                (rule.get("gunas") or []) + modifier_gunas,
                None,
            ),
            "seasons": [],
            "tier": "estimated",
            "thermal": normalize_thermal(rule.get("virya")),
            "engineExcluded": False,
        }

    def append_candidate(
        *,
        food_id,
        name,
        categories,
        allergens,
        energy,
        protein,
        carbs,
        fat,
        fiber,
        enforced_age,
        resolved,
        recipe_dosha=None,
        recipe_seasons=None,
    ):
        if food_id <= 0 or energy <= 0:
            return
        concepts = set(concepts_by_id.get(food_id, set()))
        concepts.update(safety_concepts(allergens))
        role_resolution = role_by_id[food_id]
        role = role_resolution["role"]
        role_definition = role_definitions[role]
        tokens = set(normalized_tokens(name))
        is_honey = "honey" in concepts or "honey" in tokens
        is_ghee = "ghee" in tokens or {
            "clarified",
            "butter",
        }.issubset(tokens)
        heated = bool(
            tokens.intersection(("heated", "cooked", "baked", "boiled", "warmed"))
        )
        if recipe_dosha is not None:
            resolved = {
                "doshaVata": int(recipe_dosha.get("vata", 0)),
                "doshaPitta": int(recipe_dosha.get("pitta", 0)),
                "doshaKapha": int(recipe_dosha.get("kapha", 0)),
                "rasa": [],
                "hasVipaka": False,
                "hasVirya": False,
                "hasPrabhava": False,
                "heaviness": 0.5,
                "seasons": sorted(
                    {
                        normalized_term(value)
                        for value in recipe_seasons or []
                    }
                ),
                "tier": "classical",
                "thermal": "unrecorded",
                "engineExcluded": False,
            }
        candidate = {
            "id": food_id,
            "name": name,
            "kcalPer100g": energy,
            "proteinPer100g": protein,
            "carbsPer100g": carbs,
            "fatPer100g": fat,
            "fiberPer100g": fiber,
            "concepts": sorted(concepts),
            "enforcedMinAgeMonths": int(enforced_age or 0),
            "engineExcluded": resolved["engineExcluded"],
            "role": role,
            "roleAnchor": role_definition["anchor"],
            "roleMaxPerMeal": role_definition["maxPerMeal"],
            "roleEligibleAsComponent": role_definition[
                "eligibleAsComponent"
            ],
            "notReadyToEat": role_resolution["notReadyToEat"],
            "roleHeadword": role_resolution["headword"],
            "minimumGrams": role_definition["portionGrams"]["min"],
            "maximumGrams": role_definition["portionGrams"]["max"],
            "doshaVata": resolved["doshaVata"],
            "doshaPitta": resolved["doshaPitta"],
            "doshaKapha": resolved["doshaKapha"],
            "rasa": resolved["rasa"],
            "hasVipaka": resolved["hasVipaka"],
            "hasVirya": resolved["hasVirya"],
            "hasPrabhava": resolved["hasPrabhava"],
            "heaviness": resolved["heaviness"],
            "seasons": resolved["seasons"],
            "tier": resolved["tier"],
            "isHoney": is_honey,
            "isGhee": is_ghee,
            "isHeatedHoney": is_honey and heated,
        }
        wrappers.append(
            {
                "candidate": candidate,
                "thermalCharacter": resolved["thermal"],
            }
        )

    for food in foods:
        food_id = int(food["id"])
        categories = food.get("category") or []
        append_candidate(
            food_id=food_id,
            name=food["name"],
            categories=categories,
            allergens=food.get("allergens"),
            energy=nutrient_value(food, "other", "energyKcal"),
            protein=nutrient_value(food, "macronutrients", "protein"),
            carbs=nutrient_value(food, "macronutrients", "carbohydrates"),
            fat=nutrient_value(food, "macronutrients", "fat"),
            fiber=nutrient_value(food, "macronutrients", "fiber"),
            enforced_age=food.get("minAgeMonths"),
            resolved=resolution(food_id, food["name"], categories),
        )

    for recipe in seed["recipes"]:
        nutrition = recipe["nutrition"]["per100g"]
        safety = recipe.get("safety") or {}
        append_candidate(
            food_id=int(recipe["foodId"]),
            name=recipe["name"],
            categories=[recipe.get("category", "")],
            allergens=safety.get("allergens"),
            energy=float(nutrition.get("energyKcal") or 0),
            protein=float(nutrition.get("protein") or 0),
            carbs=float(nutrition.get("carbohydrates") or 0),
            fat=float(nutrition.get("fat") or 0),
            fiber=float(nutrition.get("fiber") or 0),
            enforced_age=safety.get("enforcedMinAgeMonths"),
            resolved={},
            recipe_dosha=recipe.get("dosha") or {},
            recipe_seasons=recipe.get("seasons") or [],
        )

    destination.write_text(
        json.dumps(wrappers, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    return len(wrappers)


class MP6NarrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mp6-narration-tests-"
        )
        temporary_root = Path(cls.temporary.name)
        pure_harness = temporary_root / "MP6PureHarness.swift"
        telemetry_harness = temporary_root / "MP6TelemetryHarness.swift"
        real_solver_harness = temporary_root / "MP6RealSolverHarness.swift"
        real_candidates = temporary_root / "real-candidates.json"
        cls.pure_binary = temporary_root / "mp6-pure-harness"
        cls.telemetry_binary = temporary_root / "mp6-telemetry-harness"
        cls.real_solver_binary = temporary_root / "mp6-real-solver-harness"
        pure_harness.write_text(PURE_HARNESS, encoding="utf-8")
        telemetry_harness.write_text(TELEMETRY_HARNESS, encoding="utf-8")
        real_solver_harness.write_text(
            REAL_SOLVER_HARNESS,
            encoding="utf-8",
        )
        cls.real_candidate_count = make_real_candidate_file(real_candidates)
        cls.real_candidates = real_candidates

        pure_compile = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(NARRATION),
                str(pure_harness),
                "-o",
                str(cls.pure_binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if pure_compile.returncode != 0:
            raise AssertionError(
                "MP-6 pure template harness did not compile:\n"
                + pure_compile.stdout
                + pure_compile.stderr
            )

        telemetry_compile = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-parse-as-library",
                str(NARRATION),
                str(REQUEST),
                str(TELEMETRY),
                str(telemetry_harness),
                "-o",
                str(cls.telemetry_binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if telemetry_compile.returncode != 0:
            raise AssertionError(
                "MP-6 telemetry harness did not compile:\n"
                + telemetry_compile.stdout
                + telemetry_compile.stderr
            )

        real_solver_compile = subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-O",
                "-parse-as-library",
                str(SOLVER),
                str(NARRATION),
                str(real_solver_harness),
                "-o",
                str(cls.real_solver_binary),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if real_solver_compile.returncode != 0:
            raise AssertionError(
                "MP-6 real solver harness did not compile:\n"
                + real_solver_compile.stdout
                + real_solver_compile.stderr
            )
        real_solver_run = subprocess.run(
            [str(cls.real_solver_binary), str(real_candidates)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if real_solver_run.returncode != 0:
            raise AssertionError(
                "MP-6 real solver harness did not complete:\n"
                + real_solver_run.stdout
                + real_solver_run.stderr
            )
        cls.real_sample = json.loads(real_solver_run.stdout)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def run_pure(self, scenario):
        result = subprocess.run(
            [str(self.pure_binary), scenario],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def run_telemetry(self, scenario, days):
        result = subprocess.run(
            [
                str(self.telemetry_binary),
                scenario,
                str(days),
                "-ayuraPlannerTelemetry",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def test_one_narration_call_for_1_3_and_7_days(self):
        for days in (1, 3, 7):
            output = self.run_telemetry("narration", days)
            self.assertIn(
                "MP1-TELEMETRY-SITE: mealPlanNarration | 1 | 1 | 0",
                output,
            )
            self.assertIn(
                f"MP6-CALL-GATE scenario=narration days={days} "
                f"closureCalls=1 titles={days * 3}",
                output,
            )

    def test_three_day_template_is_complete_and_readable(self):
        records = json.loads(self.run_pure("template3"))
        self.assertEqual(len(records), 9)
        for record in records:
            copy = record["title"]
            self.assertGreater(len(copy), 45)
            self.assertRegex(copy, r"\d+ kcal")
            self.assertRegex(copy, r"\d+\.\d g protein")
            self.assertNotIn("for balanced agni", copy)
            self.assertNotIn("Traditionally considered mixed", copy)

        by_key = {
            (record["day"], record["slotIndex"]): record["title"]
            for record in records
        }
        self.assertIn("Recorded tastes:", by_key[(1, 0)])
        self.assertIn("Traditionally considered warming.", by_key[(1, 0)])
        self.assertNotIn("agni context", by_key[(1, 0)])
        self.assertNotIn("Traditionally considered", by_key[(1, 1)])
        self.assertNotIn("agni context", by_key[(1, 1)])
        self.assertIn(
            "with sweet as its recorded taste",
            by_key[(1, 2)],
        )
        self.assertNotIn("Recorded taste", by_key[(1, 2)])
        self.assertIn("Traditionally considered cooling.", by_key[(1, 2)])
        self.assertIn("Traditional agni context: slow.", by_key[(2, 1)])
        self.assertNotIn("mixed", by_key[(2, 1)])

    def test_five_frames_are_deterministic_and_never_repeat_adjacent(self):
        frames = [int(value) for value in self.run_pure("frames7").split(",")]
        self.assertEqual(len(frames), 21)
        self.assertEqual(set(frames), set(range(5)))
        self.assertTrue(
            all(left != right for left, right in zip(frames, frames[1:]))
        )
        self.assertEqual(
            {frame: frames.count(frame) for frame in range(5)},
            {0: 5, 1: 4, 2: 4, 3: 4, 4: 4},
        )

    def test_real_solver_seven_day_template_sample(self):
        sample = self.real_sample
        self.assertEqual(
            sample["candidateSource"],
            "shipped foods.json + ayurveda_seed.json.gz",
        )
        self.assertEqual(
            sample["sourceCandidateCount"],
            self.real_candidate_count,
        )
        self.assertGreater(sample["sourceCandidateCount"], 13_500)
        self.assertTrue(sample["twoDayNoRepeat"])
        self.assertGreaterEqual(sample["distinctFoodCount"], 25)
        meals = sample["meals"]
        self.assertEqual(len(meals), 21)
        frames = [meal["frameIndex"] for meal in meals]
        self.assertTrue(
            all(left != right for left, right in zip(frames, frames[1:]))
        )
        self.assertTrue(all(meal["componentIDs"] for meal in meals))
        self.assertTrue(all(meal["title"].strip() for meal in meals))

    def test_title_count_mismatch_falls_back_without_misassignment(self):
        output = self.run_pure("mismatch")
        self.assertEqual(
            output,
            "MP6-MISMATCH calls=1 fallback=true count=9 "
            "reason=title count or index mismatch",
        )

    def test_wall_clock_budget_falls_back(self):
        output = self.run_pure("timeout")
        self.assertEqual(
            output,
            "MP6-TIMEOUT fallback=true count=3 "
            "reason=narration exceeded wall-clock budget",
        )

    def test_template_is_deterministic_and_has_no_foundation_models_link(self):
        self.assertEqual(
            self.run_pure("determinism"),
            "PASS determinism",
        )
        linkage = subprocess.run(
            ["otool", "-L", str(self.pure_binary)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertNotIn("FoundationModels", linkage)
        self.assertNotIn(
            "FoundationModels",
            NARRATION.read_text(encoding="utf-8"),
        )

    def test_end_to_end_seven_day_model_call_total_is_two(self):
        output = self.run_telemetry("endtoend", 7)
        self.assertIn(
            "MP1-TELEMETRY: label=mp6-endtoend-7 "
            "total sessions=2 total responds=2 total failed responds=0",
            output,
        )
        self.assertIn(
            "MP1-TELEMETRY-SITE: mealPlanIntentParse | 1 | 1 | 0",
            output,
        )
        self.assertIn(
            "MP1-TELEMETRY-SITE: mealPlanNarration | 1 | 1 | 0",
            output,
        )
        self.assertIn(
            "MP6-CALL-GATE scenario=endtoend days=7 "
            "closureCalls=2 titles=21",
            output,
        )

    def test_schema_safety_rules_wiring_and_deletions(self):
        narrator = FOUNDATION_MODELS_NARRATOR.read_text(encoding="utf-8")
        planner = PLANNER.read_text(encoding="utf-8")
        models = MODELS.read_text(encoding="utf-8")
        self.assertIn("@Generable", narrator)
        self.assertIn("let titles: [MP6GeneratedNarrationTitle]", narrator)
        self.assertEqual(narrator.count("session.respond("), 1)
        for rule in (
            "Never invent, replace, recommend, or omit a food.",
            "Never invent a weight, calorie, protein, taste, thermal, agni",
            "treats, cures, prevents, or",
            'use the register "Traditionally considered"',
            "qualityState aiDraft pending expert review",
        ):
            self.assertIn(rule, narrator)
        self.assertIn("MP6MealPlanNarrator.narrate(", planner)
        self.assertIn("assembly.narrationFacts", planner)
        self.assertIn(
            ".descriptiveTitle = narratedTitle.title",
            planner,
        )
        for deleted in (
            "aiPolishTitle",
            "diversifyDescriptiveTitlesIfNeeded",
        ):
            self.assertNotIn(deleted, planner)
            self.assertNotIn(deleted, models)


if __name__ == "__main__":
    unittest.main()
