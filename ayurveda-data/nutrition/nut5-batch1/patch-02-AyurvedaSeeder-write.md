# Patch 02 — write emitted dravya panels onto placeholder FoodItems

Companion to `patch-01-build_seed-emit.diff`. Apply after it.

## Where

`Ayura/Main/DBSeed/AyurvedaSeeder.swift`, in the placeholder loop that currently reads:

```swift
for dravya in seed.dravyas where dravya.foodIsPlaceholder {
    if foodByID[dravya.foodId] == nil {
        let food = FoodItem(
            id: dravya.foodId,
            name: dravya.name,
            isRecipe: false,
            isUserAdded: false,
            itemDescription: dravyaDescription(dravya)
        )
        context.insert(food)
        foodByID[dravya.foodId] = food
        result.insertedFoods += 1
    } else if let food = foodByID[dravya.foodId],
              food.itemDescription != dravyaDescription(dravya) {
        food.itemDescription = dravyaDescription(dravya)
        result.updatedDravyaFoods += 1
    }
}
```

## Change

After the insert/update branch, and still inside the same loop, apply the panel:

```swift
    if let food = foodByID[dravya.foodId],
       applyDravyaNutrition(dravya.nutrition, to: food) {
        result.nutritionAppliedFoods += 1
    }
```

Add `nutritionAppliedFoods` to `RunResult` alongside `updatedDravyaFoods`, and include it in
the printed summary and in `hasChanges` / `deletedRows`-style accounting exactly as the
existing counters are.

## The helper

`referenceWeightG` for a non-recipe food is `other?.weightG?.value ?? 100`, so a placeholder
with no explicit weight is already on a per-100 g basis. The emitted panel is per 100 g.
They agree, so values are written straight through with no scaling. **Do not scale**, and do
not set `other.weightG` — inventing a weight would silently rescale every value.

```swift
/// Writes a measured per-100 g panel onto a placeholder food.
///
/// The panel arrives from dravya_foods.json through build_seed.py, which has
/// already dropped every nutrient whose source value was null. A nutrient
/// absent from the panel is unsourced and must stay absent — never zero.
/// Returns true when anything was written.
@discardableResult
private static func applyDravyaNutrition(
    _ nutrition: AyurvedaSeedDTO.DravyaNutrition?,
    to food: FoodItem
) -> Bool {
    guard let nutrition, !nutrition.per100g.isEmpty else { return false }

    func nutrient(_ key: String) -> Nutrient? {
        guard let value = nutrition.per100g[key],
              let unit = nutrition.units[key] else { return nil }
        return Nutrient(value: value, unit: unit)
    }

    let macros = MacronutrientsData(
        carbohydrates: nutrient("carbohydrates"),
        protein: nutrient("protein"),
        fat: nutrient("fat"),
        fiber: nutrient("fiber"),
        totalSugars: nutrient("totalSugars")
    )
    let vitamins = VitaminsData(
        vitaminA_RAE: nutrient("vitaminA_RAE"),
        retinol: nutrient("retinol"),
        caroteneAlpha: nutrient("caroteneAlpha"),
        caroteneBeta: nutrient("caroteneBeta"),
        cryptoxanthinBeta: nutrient("cryptoxanthinBeta"),
        luteinZeaxanthin: nutrient("luteinZeaxanthin"),
        lycopene: nutrient("lycopene"),
        vitaminB1_Thiamin: nutrient("vitaminB1_Thiamin"),
        vitaminB2_Riboflavin: nutrient("vitaminB2_Riboflavin"),
        vitaminB3_Niacin: nutrient("vitaminB3_Niacin"),
        vitaminB5_PantothenicAcid: nutrient("vitaminB5_PantothenicAcid"),
        vitaminB6: nutrient("vitaminB6"),
        folateDFE: nutrient("folateDFE"),
        folateFood: nutrient("folateFood"),
        folateTotal: nutrient("folateTotal"),
        folicAcid: nutrient("folicAcid"),
        vitaminB12: nutrient("vitaminB12"),
        vitaminC: nutrient("vitaminC"),
        vitaminD: nutrient("vitaminD"),
        vitaminE: nutrient("vitaminE"),
        vitaminK: nutrient("vitaminK"),
        choline: nutrient("choline")
    )
    let minerals = MineralsData(
        calcium: nutrient("calcium"),
        iron: nutrient("iron"),
        magnesium: nutrient("magnesium"),
        phosphorus: nutrient("phosphorus"),
        potassium: nutrient("potassium"),
        sodium: nutrient("sodium"),
        selenium: nutrient("selenium"),
        zinc: nutrient("zinc"),
        copper: nutrient("copper"),
        manganese: nutrient("manganese"),
        fluoride: nutrient("fluoride")
    )
    let other = OtherCompoundsData(energyKcal: nutrient("energyKcal"))

    food.macronutrients = macros
    food.vitamins = vitamins
    food.minerals = minerals
    food.other = other
    return true
}
```

The key list mirrors `FoodItem.aggregatedNutrition`'s recipe branch exactly, so the two paths
cannot drift. If `NUTRIENT_CATALOG` gains a nutrient, both lists need it — the existing
catalogue-drift test should be extended to assert that.

## DTO

Add to `AyurvedaSeedDTO`'s dravya type:

```swift
struct DravyaNutrition: Decodable {
    let status: String
    let per100g: [String: Double]
    let units: [String: String]
}
var nutrition: DravyaNutrition?
```

Optional, because a dravya bound to a real USDA row emits `null` — it already carries that
row's nutrition on the food itself.

## Gate

- `nutritionAppliedFoods` must equal the number of placeholder dravyas whose panel is
  non-empty. With the current data that is **73**; after the sourcing work in this batch it
  will be higher, so read it from the seed rather than pinning a literal.
- Assert no food gained a `0` where its source value was null. Spot-check `900005`
  `Agathi leaf`: it must come out with 33 nutrients present, and `ZMACRONUTRIENTS` non-NULL
  in the exported preseed.
- Assert `dravya.aam-panna` behaviour matches whatever its panel ends up being — absent
  panel means the row still has no nutrient blobs, which is correct and must not become
  zeros.
