//AIFoodDetailModels.swift

import FoundationModels

@available(iOS 26.0, *)
@Generable
struct AIBestMatchResponse: Codable {
    @Guide(description: "The name of the best matching food from the provided list, or null if no item is a good match.")
    var bestMatch: String?
}

@available(iOS 26.0, *)
@Generable
struct AIDescriptionResponse: Codable {
    @Guide(description: "A brief, engaging description of the food item.")
    var description: String
}

@available(iOS 26.0, *)
@Generable
struct AIMinAgeResponse: Codable {
    @Guide(description: "The recommended minimum age in months for a child to consume this food. Use 0 if suitable for all ages.")
    var minAgeMonths: Int
}

// --- START OF CHANGE: tolerant AINutrient decoder ---
@available(iOS 26.0, *)
@Generable
struct AINutrient: Codable {
    var value: Double
    var unit: String

    init(value: Double, unit: String) {
        self.value = value
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case value, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let v = try? c.decode(Double.self, forKey: .value) {
            self.value = v
        } else if let s = try? c.decode(String.self, forKey: .value) {
            self.value = AINutrient.parseNumeric(s)
        } else {
            // ако нищо не можем да извадим – приемаме 0
            self.value = 0
        }

        self.unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(unit, forKey: .unit)
    }

    private static func parseNumeric(_ raw: String) -> Double {
        // допуска "0.12", "0,12", "<0.1", ">1.2", "trace", "tr", "na", "n/a", "-", "—"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["na", "n/a", "trace", "tr", "-", "—"].contains(trimmed) { return 0 }

        var s = trimmed.replacingOccurrences(of: ",", with: ".")
        // махаме всичко различно от цифри, знак, точка, e/E
        s = s.replacingOccurrences(of: "[^0-9.+\\-eE]", with: "", options: .regularExpression)
        return Double(s) ?? 0
    }
}
// --- END OF CHANGE ---


@available(iOS 26.0, *)
@Generable
struct AICarbohydratesResponse: Codable {
    @Guide(description: "Total carbohydrates (per 100 g). Unit: 'g'.")
    var carbohydrates: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIProteinResponse: Codable {
    @Guide(description: "Total protein (per 100 g). Unit: 'g'.")
    var protein: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIFatResponse: Codable {
    @Guide(description: "Total fat (per 100 g). Unit: 'g'.")
    var fat: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIFiberResponse: Codable {
    @Guide(description: "Dietary fiber (per 100 g). Unit: 'g'.")
    var fiber: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AITotalSugarsResponse: Codable {
    @Guide(description: "Total sugars (per 100 g). Unit: 'g'.")
    var totalSugars: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIMacronutrients: Codable {
    var carbohydrates: AINutrient
    
    var protein: AINutrient
    
    var fat: AINutrient
    
    var fiber: AINutrient
    
    var totalSugars: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIMacrosResponse: Codable {
    var macronutrients: AIMacronutrients
}

@available(iOS 26.0, *)
@Generable
enum AIGenFoodCategory: String, Codable, CaseIterable {
    case americanIndianAlaskaNativeFoods = "American Indian/Alaska Native Foods"
    case appleJuice = "Apple juice"
    case apples = "Apples"
    case avocado = "Avocado"
    case babyFoods = "Baby Foods"
    case babyFoodCereals = "Baby food: cereals"
    case babyFoodFruit = "Baby food: fruit"
    case babyFoodMeatAndDinners = "Baby food: meat and dinners"
    case babyFoodMixtures = "Baby food: mixtures"
    case babyFoodSnacksAndSweets = "Baby food: snacks and sweets"
    case babyFoodVegetables = "Baby food: vegetables"
    case babyFoodYogurt = "Baby food: yogurt"
    case babyJuice = "Baby juice"
    case babyWater = "Baby water"
    case bacon = "Bacon"
    case bagelsAndEnglishMuffins = "Bagels and English muffins"
    case bakedProducts = "Baked Products"
    case bananas = "Bananas"
    case bean = "Bean"
    case beans = "Beans"
    case beef = "Beef"
    case beefProducts = "Beef Products"
    case beer = "Beer"
    case beverages = "Beverages"
    case biscuits = "Biscuits"
    case blueberriesAndOtherBerries = "Blueberries and other berries"
    case bottledWater = "Bottled water"
    case breakfastCereals = "Breakfast Cereals"
    case broccoli = "Broccoli"
    case burgers = "Burgers"
    case burritosAndTacos = "Burritos and tacos"
    case butterAndAnimalFats = "Butter and animal fats"
    case cabbage = "Cabbage"
    case cakesAndPies = "Cakes and pies"
    case candyContainingChocolate = "Candy containing chocolate"
    case candyNotContainingChocolate = "Candy not containing chocolate"
    case carrots = "Carrots"
    case cerealGrainsAndPasta = "Cereal Grains and Pasta"
    case cerealBars = "Cereal bars"
    case cheese = "Cheese"
    case cheeseSandwiches = "Cheese sandwiches"
    case chicken = "Chicken"
    case chickenFilletSandwiches = "Chicken fillet sandwiches"
    case chickenPatties = "Chicken patties"
    case citrusFruits = "Citrus fruits"
    case citrusJuice = "Citrus juice"
    case coffee = "Coffee"
    case coldCutsAndCuredMeats = "Cold cuts and cured meats"
    case coleslaw = "Coleslaw"
    case cookiesAndBrownies = "Cookies and brownies"
    case corn = "Corn"
    case cottageRicottaCheese = "Cottage/ricotta cheese"
    case crackers = "Crackers"
    case creamAndCreamSubstitutes = "Cream and cream substitutes"
    case creamCheese = "Cream cheese"
    case dairyAndEggProducts = "Dairy and Egg Products"
    case deliAndCuredMeatSandwiches = "Deli and cured meat sandwiches"
    case dietSoftDrinks = "Diet soft drinks"
    case dietSportAndEnergyDrinks = "Diet sport and energy drinks"
    case dips = "Dips"
    case doughnuts = "Doughnuts"
    case driedFruits = "Dried fruits"
    case eggRolls = "Egg rolls"
    case eggBreakfastSandwiches = "Egg/breakfast sandwiches"
    case eggsAndOmelets = "Eggs and omelets"
    case enhancedWater = "Enhanced water"
    case entrees = "Entrees"
    case fastFoods = "Fast Foods"
    case fatsAndOils = "Fats and Oils"
    case finfishAndShellfishProducts = "Finfish and Shellfish Products"
    case fish = "Fish"
    case flavoredMilk = "Flavored milk"
    case flavoredOrCarbonatedWater = "Flavored or carbonated water"
    case formula = "Formula"
    case frankfurterSandwiches = "Frankfurter sandwiches"
    case frankfurters = "Frankfurters"
    case frenchFriesAndOtherFriedWhitePotatoes = "French fries and other fried white potatoes"
    case frenchToast = "French toast"
    case friedRiceAndLoChowMein = "Fried rice and lo/chow mein"
    case friedVegetables = "Fried vegetables"
    case fruitDrinks = "Fruit drinks"
    case fruitsAndFruitJuices = "Fruits and Fruit Juices"
    case gelatins = "Gelatins"
    case grapes = "Grapes"
    case greek = "Greek"
    case gritsAndOtherCookedCereals = "Grits and other cooked cereals"
    case groundBeef = "Ground beef"
    case iceCreamAndFrozenDairyDesserts = "Ice cream and frozen dairy desserts"
    case jams = "Jams"
    case lamb = "Lamb"
    case legumesAndLegumeProducts = "Legumes and Legume Products"
    case lettuceAndLettuceSalads = "Lettuce and lettuce salads"
    case liquorAndCocktails = "Liquor and cocktails"
    case liverAndOrganMeats = "Liver and organ meats"
    case macaroniAndCheese = "Macaroni and cheese"
    case mangoAndPapaya = "Mango and papaya"
    case margarine = "Margarine"
    case mashedPotatoesAndWhitePotatoMixtures = "Mashed potatoes and white potato mixtures"
    case mayonnaise = "Mayonnaise"
    case meals = "Meals"
    case meatAndBbqSandwiches = "Meat and BBQ sandwiches"
    case meatMixedDishes = "Meat mixed dishes"
    case melons = "Melons"
    case milk = "Milk"
    case milkShakesAndOtherDairyDrinks = "Milk shakes and other dairy drinks"
    case mustardAndOtherCondiments = "Mustard and other condiments"
    case nachos = "Nachos"
    case notIncludedInAFoodCategory = "Not included in a food category"
    case nutAndSeedProducts = "Nut and Seed Products"
    case nutritionBars = "Nutrition bars"
    case nutritionalBeverages = "Nutritional beverages"
    case nutsAndSeeds = "Nuts and seeds"
    case oatmeal = "Oatmeal"
    case olives = "Olives"
    case onions = "Onions"
    case otherMexicanMixedDishes = "Other Mexican mixed dishes"
    case otherDarkGreenVegetables = "Other dark green vegetables"
    case otherDietDrinks = "Other diet drinks"
    case otherFruitJuice = "Other fruit juice"
    case otherFruitsAndFruitSalads = "Other fruits and fruit salads"
    case otherRedAndOrangeVegetables = "Other red and orange vegetables"
    case otherStarchyVegetables = "Other starchy vegetables"
    case otherVegetablesAndCombinations = "Other vegetables and combinations"
    case pancakes = "Pancakes"
    case pasta = "Pasta"
    case pastaMixedDishes = "Pasta mixed dishes"
    case pastaSauces = "Pasta sauces"
    case peachesAndNectarines = "Peaches and nectarines"
    case peanutButterAndJellySandwiches = "Peanut butter and jelly sandwiches"
    case pears = "Pears"
    case pineapple = "Pineapple"
    case pizza = "Pizza"
    case plantBasedMilk = "Plant-based milk"
    case plantBasedYogurt = "Plant-based yogurt"
    case popcorn = "Popcorn"
    case pork = "Pork"
    case porkProducts = "Pork Products"
    case potatoChips = "Potato chips"
    case poultryProducts = "Poultry Products"
    case poultryMixedDishes = "Poultry mixed dishes"
    case pretzelsSnackMix = "Pretzels/snack mix"
    case proteinAndNutritionalPowders = "Protein and nutritional powders"
    case pudding = "Pudding"
    case ramenAndAsianBrothBasedSoups = "Ramen and Asian broth-based soups"
    case readyToEatCereal = "Ready-to-eat cereal"
    case restaurantFoods = "Restaurant Foods"
    case rice = "Rice"
    case riceMixedDishes = "Rice mixed dishes"
    case rollsAndBuns = "Rolls and buns"
    case saladDressingsAndVegetableOils = "Salad dressings and vegetable oils"
    case saltineCrackers = "Saltine crackers"
    case sauces = "Sauces"
    case sausages = "Sausages"
    case sausagesAndLuncheonMeats = "Sausages and Luncheon Meats"
    case seafoodMixedDishes = "Seafood mixed dishes"
    case seafoodSandwiches = "Seafood sandwiches"
    case shellfish = "Shellfish"
    case smoothiesAndGrainDrinks = "Smoothies and grain drinks"
    case snacks = "Snacks"
    case softDrinks = "Soft drinks"
    case soups = "Soups"
    case soyAndMeatAlternativeProducts = "Soy and meat-alternative products"
    case soyBasedCondiments = "Soy-based condiments"
    case spicesAndHerbs = "Spices and Herbs"
    case spinach = "Spinach"
    case sportAndEnergyDrinks = "Sport and energy drinks"
    case stirFryAndSoyBasedSauceMixtures = "Stir-fry and soy-based sauce mixtures"
    case strawberries = "Strawberries"
    case stringBeans = "String beans"
    case sugarSubstitutes = "Sugar substitutes"
    case sugarsAndHoney = "Sugars and honey"
    case sweets = "Sweets"
    case tapWater = "Tap water"
    case tea = "Tea"
    case tomatoBasedCondiments = "Tomato-based condiments"
    case tomatoes = "Tomatoes"
    case tortilla = "Tortilla"
    case tortillas = "Tortillas"
    case turkey = "Turkey"
    case turnoversAndOtherGrainBasedItems = "Turnovers and other grain-based items"
    case veal = "Veal"
    case vegetableDishes = "Vegetable dishes"
    case vegetableJuice = "Vegetable juice"
    case vegetableSandwichesBurgers = "Vegetable sandwiches/burgers"
    case vegetablesAndVegetableProducts = "Vegetables and Vegetable Products"
    case vegetablesOnASandwich = "Vegetables on a sandwich"
    case whitePotatoes = "White potatoes"
    case wine = "Wine"
    case yeastBreads = "Yeast breads"
    case yogurt = "Yogurt"
    case andGameProducts = "and Game Products"
    case andGravies = "and Gravies"
    case andSideDishes = "and Side Dishes"
    case bakedOrBoiled = "baked or boiled"
    case brothBased = "broth-based"
    case cookedGrains = "cooked grains"
    case corn_2 = "corn"
    case creamBased = "cream-based"
    case duck = "duck"
    case dumplings = "dumplings"
    case excludesGround = "excludes ground"
    case excludesMacaroniAndCheese = "excludes macaroni and cheese"
    case excludesSaltines = "excludes saltines"
    case game = "game"
    case goat = "goat"
    case gravies = "gravies"
    case higherSugar212G100G = "higher sugar (>21.2g/100g)"
    case ices = "ices"
    case legumeDishes = "legume dishes"
    case legumes = "legumes"
    case lowerSugar212G100G = "lower sugar (=<21.2g/100g)"
    case lowfat = "lowfat"
    case muffins = "muffins"
    case nonLettuceSalads = "non-lettuce salads"
    case nonfat = "nonfat"
    case noodles = "noodles"
    case nuggetsAndTenders = "nuggets and tenders"
    case otherChips = "other chips"
    case otherPoultry = "other poultry"
    case otherSauces = "other sauces"
    case pastries = "pastries"
    case pea = "pea"
    case peas = "peas"
    case pickledVegetables = "pickled vegetables"
    case pickles = "pickles"
    case preparedFromPowder = "prepared from powder"
    case quickBreads = "quick breads"
    case readyToFeed = "ready-to-feed"
    case reducedFat = "reduced fat"
    case regular = "regular"
    case sorbets = "sorbets"
    case sourCream = "sour cream"
    case sushi = "sushi"
    case sweetRolls = "sweet rolls"
    case syrups = "syrups"
    case tomatoBased = "tomato-based"
    case toppings = "toppings"
    case waffles = "waffles"
    case whippedCream = "whipped cream"
    case whole = "whole"
    case wholePieces = "whole pieces"
}


@available(iOS 26.0, *)
@Generable
struct AICategoriesResponse: Codable {
    @Guide(description: "An array of relevant food categories for this item.")
    var categories: [AIGenFoodCategory]
}

@available(iOS 26.0, *)
@Generable
enum AIGenAllergen: String, Codable, CaseIterable {
    case celery = "Celery"
    case cerealsContainingGluten = "Cereals containing gluten"
    case cerealsContainingGlutenBarley = "Cereals containing gluten (barley)"
    case cerealsContainingGlutenOats = "Cereals containing gluten (oats)"
    case cerealsContainingGlutenRye = "Cereals containing gluten (rye)"
    case crustaceans = "Crustaceans"
    case eggs = "Eggs"
    case fish = "Fish"
    case lowSodium = "Low Sodium"
    case milk = "Milk"
    case molluscs = "Molluscs"
    case mustard = "Mustard"
    case nuts = "Nuts"
    case nutsBrazilNuts = "Nuts (Brazil nuts)"
    case nutsAlmonds = "Nuts (almonds)"
    case nutsCashews = "Nuts (cashews)"
    case nutsChestnuts = "Nuts (chestnuts)"
    case nutsCoconut = "Nuts (coconut)"
    case nutsHazelnuts = "Nuts (hazelnuts)"
    case nutsMacadamiaNuts = "Nuts (macadamia nuts)"
    case nutsPecans = "Nuts (pecans)"
    case nutsPineNuts = "Nuts (pine nuts)"
    case nutsPistachioNuts = "Nuts (pistachio nuts)"
    case nutsWalnuts = "Nuts (walnuts)"
    case peanuts = "Peanuts"
    case sesameSeeds = "Sesame seeds"
    case soybeans = "Soybeans"
    case sulphurDioxideSulphites = "Sulphur dioxide/sulphites"
}

@available(iOS 26.0, *)
@Generable
struct AIAllergensResponse: Codable {
    @Guide(description: "An array of common allergens present in this food.")
    var allergens: [AIGenAllergen]
}

@available(iOS 26.0, *)
@Generable
struct AIDietsResponse: Codable {
    @Guide(description: "An array of dietary classifications (e.g., Vegan, Gluten-Free).")
    var diets: [String]
}

@available(iOS 26.0, *)
@Generable
struct AIAlcoholEthylResponse: Codable {
    @Guide(description: "Ethyl alcohol content (per 100 g). Unit: 'g'. Omit if N/A.")
    var alcoholEthyl: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AICaffeineResponse: Codable {
    @Guide(description: "Caffeine (per 100 g). Unit: 'mg'. Omit if N/A.")
    var caffeine: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AITheobromineResponse: Codable {
    @Guide(description: "Theobromine (per 100 g). Unit: 'mg'. Omit if N/A.")
    var theobromine: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AICholesterolResponse: Codable {
    @Guide(description: "Cholesterol (per 100 g). Unit: 'mg'. Omit if N/A.")
    var cholesterol: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIEnergyKcalResponse: Codable {
    @Guide(description: "Total energy (per 100 g). Unit: 'kcal'.")
    var energyKcal: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIWaterResponse: Codable {
    @Guide(description: "Water (per 100 g). Unit: 'g'. Omit if N/A.")
    var water: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIWeightGResponse: Codable {
    @Guide(description: "Reference serving weight for ALL provided nutrients. MUST be exactly 100 g. Unit: 'g'.")
    var weightG: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIAshResponse: Codable {
    @Guide(description: "Ash (per 100 g). Unit: 'g'. Omit if N/A.")
    var ash: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIBetaineResponse: Codable {
    @Guide(description: "Betaine (per 100 g). Unit: 'mg'. Omit if N/A.")
    var betaine: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIAlkalinityPHResponse: Codable {
    @Guide(description: "The potential hydrogen (pH) level of the food, indicating its acidity or alkalinity. The value should be a number, and the unit should be 'pH'. Provide a value of 7.0 for neutral foods like pure water. Omit if not applicable.")
    var alkalinityPH: AINutrient
}

@available(iOS 26.0, *)
struct AIOtherCompounds: Codable {
    var alcoholEthyl: AINutrient

    var caffeine: AINutrient

    var theobromine: AINutrient

    var cholesterol: AINutrient

    var energyKcal: AINutrient

    var water: AINutrient

    var weightG: AINutrient

    var ash: AINutrient

    var betaine: AINutrient
    
    var alkalinityPH: AINutrient
}

@available(iOS 26.0, *)
struct AIOtherResponse: Codable {
    var other: AIOtherCompounds
}

@available(iOS 26.0, *) @Generable struct AIVitA_RAE_Resp: Codable { @Guide(description:"Vitamin A activity as RAE per 100 g. Unit: 'µg'.") var vitaminA_RAE: AINutrient }
@available(iOS 26.0, *) @Generable struct AIRetinol_Resp: Codable { @Guide(description:"Retinol per 100 g. Unit: 'µg'.") var retinol: AINutrient }
@available(iOS 26.0, *) @Generable struct AICaroteneAlpha_Resp: Codable { @Guide(description:"Alpha-carotene per 100 g. Unit: 'µg'.") var caroteneAlpha: AINutrient }
@available(iOS 26.0, *) @Generable struct AICaroteneBeta_Resp: Codable { @Guide(description:"Beta-carotene per 100 g. Unit: 'µg'.") var caroteneBeta: AINutrient }
@available(iOS 26.0, *) @Generable struct AICryptoxanthinBeta_Resp: Codable { @Guide(description:"Beta-cryptoxanthin per 100 g. Unit: 'µg'.") var cryptoxanthinBeta: AINutrient }
@available(iOS 26.0, *) @Generable struct AILuteinZeaxanthin_Resp: Codable { @Guide(description:"Lutein+zeaxanthin per 100 g. Unit: 'µg'.") var luteinZeaxanthin: AINutrient }
@available(iOS 26.0, *) @Generable struct AILycopene_Resp: Codable { @Guide(description:"Lycopene per 100 g. Unit: 'µg'.") var lycopene: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB1_Resp: Codable { @Guide(description:"Thiamin (B1) per 100 g. Unit: 'mg'.") var vitaminB1_Thiamin: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB2_Resp: Codable { @Guide(description:"Riboflavin (B2) per 100 g. Unit: 'mg'.") var vitaminB2_Riboflavin: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB3_Resp: Codable { @Guide(description:"Niacin (B3) per 100 g. Unit: 'mg'.") var vitaminB3_Niacin: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB5_Resp: Codable { @Guide(description:"Pantothenic acid (B5) per 100 g. Unit: 'mg'.") var vitaminB5_PantothenicAcid: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB6_Resp: Codable { @Guide(description:"Vitamin B6 per 100 g. Unit: 'mg'.") var vitaminB6: AINutrient }
@available(iOS 26.0, *) @Generable struct AIFolateDFE_Resp: Codable { @Guide(description:"Folate DFE per 100 g. Unit: 'µg'.") var folateDFE: AINutrient }
@available(iOS 26.0, *) @Generable struct AIFolateFood_Resp: Codable { @Guide(description:"Folate (food) per 100 g. Unit: 'µg'.") var folateFood: AINutrient }
@available(iOS 26.0, *) @Generable struct AIFolateTotal_Resp: Codable { @Guide(description:"Folate, total per 100 g. Unit: 'µg'.") var folateTotal: AINutrient }
@available(iOS 26.0, *) @Generable struct AIFolicAcid_Resp: Codable { @Guide(description:"Folic acid per 100 g. Unit: 'µg'.") var folicAcid: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitB12_Resp: Codable { @Guide(description:"Vitamin B12 per 100 g. Unit: 'µg'.") var vitaminB12: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitC_Resp: Codable { @Guide(description:"Vitamin C per 100 g. Unit: 'mg'.") var vitaminC: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitD_Resp: Codable { @Guide(description:"Vitamin D per 100 g. Unit: 'µg'.") var vitaminD: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitE_Resp: Codable { @Guide(description:"Vitamin E (alpha-tocopherol) per 100 g. Unit: 'mg'.") var vitaminE: AINutrient }
@available(iOS 26.0, *) @Generable struct AIVitK_Resp: Codable { @Guide(description:"Vitamin K per 100 g. Unit: 'µg'.") var vitaminK: AINutrient }
@available(iOS 26.0, *) @Generable struct AICholine_Resp: Codable { @Guide(description:"Choline per 100 g. Unit: 'mg'.") var choline: AINutrient }


@available(iOS 26.0, *)
@Generable
struct AIVitamins: Codable {
    var vitaminA_RAE: AINutrient

    var retinol: AINutrient

    var caroteneAlpha: AINutrient

    var caroteneBeta: AINutrient

    var cryptoxanthinBeta: AINutrient

    var luteinZeaxanthin: AINutrient

    var lycopene: AINutrient

    var vitaminB1_Thiamin: AINutrient

    var vitaminB2_Riboflavin: AINutrient

    var vitaminB3_Niacin: AINutrient

    var vitaminB5_PantothenicAcid: AINutrient

    var vitaminB6: AINutrient

    var folateDFE: AINutrient

    var folateFood: AINutrient

    var folateTotal: AINutrient

    var folicAcid: AINutrient

    var vitaminB12: AINutrient

    var vitaminC: AINutrient

    var vitaminD: AINutrient

    var vitaminE: AINutrient

    var vitaminK: AINutrient

    var choline: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIVitaminsResponse: Codable {
    var vitamins: AIVitamins
}

@available(iOS 26.0, *) @Generable struct AICalcium_Resp: Codable   { @Guide(description:"Calcium per 100 g. Unit: 'mg'.")   var calcium: AINutrient }
@available(iOS 26.0, *) @Generable struct AIIron_Resp: Codable      { @Guide(description:"Iron per 100 g. Unit: 'mg'.")      var iron: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMagnesium_Resp: Codable { @Guide(description:"Magnesium per 100 g. Unit: 'mg'.") var magnesium: AINutrient }
@available(iOS 26.0, *) @Generable struct AIPhosphorus_Resp: Codable{ @Guide(description:"Phosphorus per 100 g. Unit: 'mg'.")var phosphorus: AINutrient }
@available(iOS 26.0, *) @Generable struct AIPotassium_Resp: Codable { @Guide(description:"Potassium per 100 g. Unit: 'mg'.") var potassium: AINutrient }
@available(iOS 26.0, *) @Generable struct AISodium_Resp: Codable    { @Guide(description:"Sodium per 100 g. Unit: 'mg'.")    var sodium: AINutrient }
@available(iOS 26.0, *) @Generable struct AISelenium_Resp: Codable  { @Guide(description:"Selenium per 100 g. Unit: 'µg'.")  var selenium: AINutrient }
@available(iOS 26.0, *) @Generable struct AIZinc_Resp: Codable      { @Guide(description:"Zinc per 100 g. Unit: 'mg'.")      var zinc: AINutrient }
@available(iOS 26.0, *) @Generable struct AICopper_Resp: Codable    { @Guide(description:"Copper per 100 g. Unit: 'mg'.")    var copper: AINutrient }
@available(iOS 26.0, *) @Generable struct AIManganese_Resp: Codable { @Guide(description:"Manganese per 100 g. Unit: 'mg'.") var manganese: AINutrient }
@available(iOS 26.0, *) @Generable struct AIFluoride_Resp: Codable  { @Guide(description:"Fluoride per 100 g. Unit: 'µg'.")  var fluoride: AINutrient }

@available(iOS 26.0, *)
@Generable
struct AIMinerals: Codable {
    var calcium: AINutrient

    var iron: AINutrient

    var magnesium: AINutrient

    var phosphorus: AINutrient

    var potassium: AINutrient

    var sodium: AINutrient

    var selenium: AINutrient

    var zinc: AINutrient

    var copper: AINutrient

    var manganese: AINutrient

    var fluoride: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIMineralsResponse: Codable {
    var minerals: AIMinerals
}

@available(iOS 26.0, *) @Generable struct AITotalSaturated_Resp: Codable         { @Guide(description:"Fatty acids, total saturated per 100 g. Unit: 'g'.")          var totalSaturated: AINutrient }
@available(iOS 26.0, *) @Generable struct AITotalMonounsaturated_Resp: Codable   { @Guide(description:"Fatty acids, total monounsaturated per 100 g. Unit: 'g'.")    var totalMonounsaturated: AINutrient }
@available(iOS 26.0, *) @Generable struct AITotalPolyunsaturated_Resp: Codable   { @Guide(description:"Fatty acids, total polyunsaturated per 100 g. Unit: 'g'.")    var totalPolyunsaturated: AINutrient }
@available(iOS 26.0, *) @Generable struct AITotalTrans_Resp: Codable             { @Guide(description:"Fatty acids, total trans per 100 g. Unit: 'g'.")               var totalTrans: AINutrient }
@available(iOS 26.0, *) @Generable struct AITotalTransMonoenoic_Resp: Codable    { @Guide(description:"Fatty acids, total trans-monoenoic per 100 g. Unit: 'g'.")    var totalTransMonoenoic: AINutrient }
@available(iOS 26.0, *) @Generable struct AITotalTransPolyenoic_Resp: Codable    { @Guide(description:"Fatty acids, total trans-polyenoic per 100 g. Unit: 'g'.")    var totalTransPolyenoic: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA4_0_Resp: Codable  { @Guide(description:"SFA 4:0 (butyric) per 100 g. Unit: 'g'.")           var sfa4_0:  AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA6_0_Resp: Codable  { @Guide(description:"SFA 6:0 (caproic) per 100 g. Unit: 'g'.")           var sfa6_0:  AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA8_0_Resp: Codable  { @Guide(description:"SFA 8:0 (caprylic) per 100 g. Unit: 'g'.")          var sfa8_0:  AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA10_0_Resp: Codable { @Guide(description:"SFA 10:0 (capric) per 100 g. Unit: 'g'.")           var sfa10_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA12_0_Resp: Codable { @Guide(description:"SFA 12:0 (lauric) per 100 g. Unit: 'g'.")           var sfa12_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA13_0_Resp: Codable { @Guide(description:"SFA 13:0 per 100 g. Unit: 'g'.")                    var sfa13_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA14_0_Resp: Codable { @Guide(description:"SFA 14:0 (myristic) per 100 g. Unit: 'g'.")         var sfa14_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA15_0_Resp: Codable { @Guide(description:"SFA 15:0 (pentadecanoic) per 100 g. Unit: 'g'.")    var sfa15_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA16_0_Resp: Codable { @Guide(description:"SFA 16:0 (palmitic) per 100 g. Unit: 'g'.")         var sfa16_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA17_0_Resp: Codable { @Guide(description:"SFA 17:0 (margaric) per 100 g. Unit: 'g'.")         var sfa17_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA18_0_Resp: Codable { @Guide(description:"SFA 18:0 (stearic) per 100 g. Unit: 'g'.")          var sfa18_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA20_0_Resp: Codable { @Guide(description:"SFA 20:0 (arachidic) per 100 g. Unit: 'g'.")        var sfa20_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA22_0_Resp: Codable { @Guide(description:"SFA 22:0 (behenic) per 100 g. Unit: 'g'.")          var sfa22_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AISFA24_0_Resp: Codable { @Guide(description:"SFA 24:0 (lignoceric) per 100 g. Unit: 'g'.")       var sfa24_0: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA14_1_Resp: Codable { @Guide(description:"MUFA 14:1 per 100 g. Unit: 'g'.")                  var mufa14_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA15_1_Resp: Codable { @Guide(description:"MUFA 15:1 per 100 g. Unit: 'g'.")                  var mufa15_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA16_1_Resp: Codable { @Guide(description:"MUFA 16:1 (palmitoleic) per 100 g. Unit: 'g'.")    var mufa16_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA17_1_Resp: Codable { @Guide(description:"MUFA 17:1 per 100 g. Unit: 'g'.")                  var mufa17_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA18_1_Resp: Codable { @Guide(description:"MUFA 18:1 (oleic; incl. isomers) per 100 g. Unit: 'g'.") var mufa18_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA20_1_Resp: Codable { @Guide(description:"MUFA 20:1 (gadoleic) per 100 g. Unit: 'g'.")       var mufa20_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA22_1_Resp: Codable { @Guide(description:"MUFA 22:1 (erucic) per 100 g. Unit: 'g'.")         var mufa22_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMUFA24_1_Resp: Codable { @Guide(description:"MUFA 24:1 (nervonic) per 100 g. Unit: 'g'.")       var mufa24_1: AINutrient }
@available(iOS 26.0, *) @Generable struct AITFA16_1_t_Resp: Codable { @Guide(description:"Trans 16:1 t per 100 g. Unit: 'g'.")              var tfa16_1_t: AINutrient }
@available(iOS 26.0, *) @Generable struct AITFA18_1_t_Resp: Codable { @Guide(description:"Trans 18:1 t per 100 g. Unit: 'g'.")              var tfa18_1_t: AINutrient }
@available(iOS 26.0, *) @Generable struct AITFA22_1_t_Resp: Codable { @Guide(description:"Trans 22:1 t per 100 g. Unit: 'g'.")              var tfa22_1_t: AINutrient }
@available(iOS 26.0, *) @Generable struct AITFA18_2_t_Resp: Codable { @Guide(description:"Trans 18:2 t per 100 g. Unit: 'g'.")              var tfa18_2_t: AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA18_2_Resp: Codable  { @Guide(description:"PUFA 18:2 (linoleic, n-6) per 100 g. Unit: 'g'.")  var pufa18_2:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA18_3_Resp: Codable  { @Guide(description:"PUFA 18:3 (incl. ALA, n-3) per 100 g. Unit: 'g'.") var pufa18_3:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA18_4_Resp: Codable  { @Guide(description:"PUFA 18:4 (stearidonic, n-3) per 100 g. Unit: 'g'.") var pufa18_4:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA20_2_Resp: Codable  { @Guide(description:"PUFA 20:2 per 100 g. Unit: 'g'.")                 var pufa20_2:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA20_3_Resp: Codable  { @Guide(description:"PUFA 20:3 per 100 g. Unit: 'g'.")                 var pufa20_3:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA20_4_Resp: Codable  { @Guide(description:"PUFA 20:4 (arachidonic, AA, n-6) per 100 g. Unit: 'g'.") var pufa20_4:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA20_5_Resp: Codable  { @Guide(description:"PUFA 20:5 (EPA, n-3) per 100 g. Unit: 'g'.")      var pufa20_5:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA21_5_Resp: Codable  { @Guide(description:"PUFA 21:5 per 100 g. Unit: 'g'.")                 var pufa21_5:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA22_4_Resp: Codable  { @Guide(description:"PUFA 22:4 per 100 g. Unit: 'g'.")                 var pufa22_4:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA22_5_Resp: Codable  { @Guide(description:"PUFA 22:5 (DPA, n-3) per 100 g. Unit: 'g'.")      var pufa22_5:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA22_6_Resp: Codable  { @Guide(description:"PUFA 22:6 (DHA, n-3) per 100 g. Unit: 'g'.")      var pufa22_6:  AINutrient }
@available(iOS 26.0, *) @Generable struct AIPUFA2_4_Resp: Codable   { @Guide(description:"PUFA 2:4 (rare/legacy) per 100 g. Unit: 'g'.")    var pufa2_4:   AINutrient }

@available(iOS 26.0, *)
@Generable
struct AILipids: Codable {
    var totalSaturated: AINutrient

    var totalMonounsaturated: AINutrient

    var totalPolyunsaturated: AINutrient

    var totalTrans: AINutrient

    var totalTransMonoenoic: AINutrient

    var totalTransPolyenoic: AINutrient

    var sfa4_0:  AINutrient

    var sfa6_0:  AINutrient

    var sfa8_0:  AINutrient

    var sfa10_0: AINutrient

    var sfa12_0: AINutrient

    var sfa13_0: AINutrient

    var sfa14_0: AINutrient

    var sfa15_0: AINutrient

    var sfa16_0: AINutrient

    var sfa17_0: AINutrient

    var sfa18_0: AINutrient

    var sfa20_0: AINutrient

    var sfa22_0: AINutrient

    var sfa24_0: AINutrient

    var mufa14_1: AINutrient

    var mufa15_1: AINutrient

    var mufa16_1: AINutrient

    var mufa17_1: AINutrient

    var mufa18_1: AINutrient

    var mufa20_1: AINutrient

    var mufa22_1: AINutrient

    var mufa24_1: AINutrient

    var tfa16_1_t: AINutrient

    var tfa18_1_t: AINutrient

    var tfa22_1_t: AINutrient

    var tfa18_2_t: AINutrient

    var pufa18_2: AINutrient

    var pufa18_3: AINutrient

    var pufa18_4: AINutrient

    var pufa20_2: AINutrient

    var pufa20_3: AINutrient

    var pufa20_4: AINutrient

    var pufa20_5: AINutrient

    var pufa21_5: AINutrient

    var pufa22_4: AINutrient

    var pufa22_5: AINutrient

    var pufa22_6: AINutrient

    var pufa2_4:  AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AILipidsResponse: Codable {
    var lipids: AILipids
}

@available(iOS 26.0, *) @Generable struct AIAlanine_Resp: Codable        { @Guide(description:"Alanine per 100 g. Unit: 'g'.")        var alanine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIArginine_Resp: Codable       { @Guide(description:"Arginine per 100 g. Unit: 'g'.")       var arginine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIAsparticAcid_Resp: Codable   { @Guide(description:"Aspartic acid per 100 g. Unit: 'g'.")  var asparticAcid: AINutrient }
@available(iOS 26.0, *) @Generable struct AICystine_Resp: Codable        { @Guide(description:"Cystine per 100 g. Unit: 'g'.")        var cystine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIGlutamicAcid_Resp: Codable   { @Guide(description:"Glutamic acid per 100 g. Unit: 'g'.")  var glutamicAcid: AINutrient }
@available(iOS 26.0, *) @Generable struct AIGlycine_Resp: Codable        { @Guide(description:"Glycine per 100 g. Unit: 'g'.")        var glycine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIHistidine_Resp: Codable      { @Guide(description:"Histidine per 100 g. Unit: 'g'.")      var histidine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIIsoleucine_Resp: Codable     { @Guide(description:"Isoleucine per 100 g. Unit: 'g'.")     var isoleucine: AINutrient }
@available(iOS 26.0, *) @Generable struct AILeucine_Resp: Codable        { @Guide(description:"Leucine per 100 g. Unit: 'g'.")        var leucine: AINutrient }
@available(iOS 26.0, *) @Generable struct AILysine_Resp: Codable         { @Guide(description:"Lysine per 100 g. Unit: 'g'.")         var lysine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIMethionine_Resp: Codable     { @Guide(description:"Methionine per 100 g. Unit: 'g'.")     var methionine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIPhenylalanine_Resp: Codable  { @Guide(description:"Phenylalanine per 100 g. Unit: 'g'.")  var phenylalanine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIProline_Resp: Codable        { @Guide(description:"Proline per 100 g. Unit: 'g'.")        var proline: AINutrient }
@available(iOS 26.0, *) @Generable struct AIThreonine_Resp: Codable      { @Guide(description:"Threonine per 100 g. Unit: 'g'.")      var threonine: AINutrient }
@available(iOS 26.0, *) @Generable struct AITryptophan_Resp: Codable     { @Guide(description:"Tryptophan per 100 g. Unit: 'g'.")     var tryptophan: AINutrient }
@available(iOS 26.0, *) @Generable struct AITyrosine_Resp: Codable       { @Guide(description:"Tyrosine per 100 g. Unit: 'g'.")       var tyrosine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIValine_Resp: Codable         { @Guide(description:"Valine per 100 g. Unit: 'g'.")         var valine: AINutrient }
@available(iOS 26.0, *) @Generable struct AISerine_Resp: Codable         { @Guide(description:"Serine per 100 g. Unit: 'g'.")         var serine: AINutrient }
@available(iOS 26.0, *) @Generable struct AIHydroxyproline_Resp: Codable { @Guide(description:"Hydroxyproline per 100 g. Unit: 'g'.") var hydroxyproline: AINutrient }

@available(iOS 26.0, *)
@Generable
struct AIAminoAcids: Codable {
    var alanine: AINutrient

    var arginine: AINutrient

    var asparticAcid: AINutrient

    var cystine: AINutrient

    var glutamicAcid: AINutrient

    var glycine: AINutrient

    var histidine: AINutrient

    var isoleucine: AINutrient

    var leucine: AINutrient

    var lysine: AINutrient

    var methionine: AINutrient

    var phenylalanine: AINutrient

    var proline: AINutrient

    var threonine: AINutrient

    var tryptophan: AINutrient

    var tyrosine: AINutrient

    var valine: AINutrient

    var serine: AINutrient

    var hydroxyproline: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AIAminoAcidsResponse: Codable {
    var aminoAcids: AIAminoAcids
}

@available(iOS 26.0, *) @Generable struct AIStarch_Resp:    Codable { @Guide(description:"Starch per 100 g. Unit: 'g'.")    var starch:    AINutrient }
@available(iOS 26.0, *) @Generable struct AISucrose_Resp:   Codable { @Guide(description:"Sucrose per 100 g. Unit: 'g'.")   var sucrose:   AINutrient }
@available(iOS 26.0, *) @Generable struct AIGlucose_Resp:   Codable { @Guide(description:"Glucose per 100 g. Unit: 'g'.")   var glucose:   AINutrient }
@available(iOS 26.0, *) @Generable struct AIFructose_Resp:  Codable { @Guide(description:"Fructose per 100 g. Unit: 'g'.")  var fructose:  AINutrient }
@available(iOS 26.0, *) @Generable struct AILactose_Resp:   Codable { @Guide(description:"Lactose per 100 g. Unit: 'g'.")   var lactose:   AINutrient }
@available(iOS 26.0, *) @Generable struct AIMaltose_Resp:   Codable { @Guide(description:"Maltose per 100 g. Unit: 'g'.")   var maltose:   AINutrient }
@available(iOS 26.0, *) @Generable struct AIGalactose_Resp: Codable { @Guide(description:"Galactose per 100 g. Unit: 'g'.") var galactose: AINutrient }

@available(iOS 26.0, *)
@Generable
struct AICarbDetails: Codable {
    var starch: AINutrient

    var sucrose: AINutrient

    var glucose: AINutrient

    var fructose: AINutrient

    var lactose: AINutrient

    var maltose: AINutrient

    var galactose: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AICarbDetailsResponse: Codable {
    var carbDetails: AICarbDetails
}

@available(iOS 26.0, *) @Generable
struct AIPhytosterols_Resp: Codable {
    @Guide(description: "Total phytosterols per 100 g. Unit: 'mg'.")
    var phytosterols: AINutrient
}

@available(iOS 26.0, *) @Generable
struct AIBetaSitosterol_Resp: Codable {
    @Guide(description: "Beta-sitosterol per 100 g. Unit: 'mg'.")
    var betaSitosterol: AINutrient
}

@available(iOS 26.0, *) @Generable
struct AICampesterol_Resp: Codable {
    @Guide(description: "Campesterol per 100 g. Unit: 'mg'.")
    var campesterol: AINutrient
}

@available(iOS 26.0, *) @Generable
struct AIStigmasterol_Resp: Codable {
    @Guide(description: "Stigmasterol per 100 g. Unit: 'mg'.")
    var stigmasterol: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AISterols: Codable {
    var phytosterols: AINutrient

    var betaSitosterol: AINutrient

    var campesterol: AINutrient

    var stigmasterol: AINutrient
}

@available(iOS 26.0, *)
@Generable
struct AISterolsResponse: Codable {
    var sterols: AISterols
}

@available(iOS 26.0, *)
extension AIVitamins {
    mutating func merge(from other: AIVitamins) {
        replaceIfZero(&vitaminA_RAE,      with: other.vitaminA_RAE)
        replaceIfZero(&retinol,           with: other.retinol)
        replaceIfZero(&caroteneAlpha,     with: other.caroteneAlpha)
        replaceIfZero(&caroteneBeta,      with: other.caroteneBeta)
        replaceIfZero(&cryptoxanthinBeta, with: other.cryptoxanthinBeta)
        replaceIfZero(&luteinZeaxanthin,  with: other.luteinZeaxanthin)
        replaceIfZero(&lycopene,          with: other.lycopene)
        replaceIfZero(&vitaminB1_Thiamin,         with: other.vitaminB1_Thiamin)
        replaceIfZero(&vitaminB2_Riboflavin,      with: other.vitaminB2_Riboflavin)
        replaceIfZero(&vitaminB3_Niacin,          with: other.vitaminB3_Niacin)
        replaceIfZero(&vitaminB5_PantothenicAcid, with: other.vitaminB5_PantothenicAcid)
        replaceIfZero(&vitaminB6,                 with: other.vitaminB6)
        replaceIfZero(&folateDFE,                 with: other.folateDFE)
        replaceIfZero(&folateFood,                with: other.folateFood)
        replaceIfZero(&folateTotal,               with: other.folateTotal)
        replaceIfZero(&folicAcid,                 with: other.folicAcid)
        replaceIfZero(&vitaminB12,                with: other.vitaminB12)
        replaceIfZero(&vitaminC, with: other.vitaminC)
        replaceIfZero(&vitaminD, with: other.vitaminD)
        replaceIfZero(&vitaminE, with: other.vitaminE)
        replaceIfZero(&vitaminK, with: other.vitaminK)
        replaceIfZero(&choline, with: other.choline)
    }
}

@available(iOS 26.0, *)
extension AIMinerals {
    mutating func merge(from other: AIMinerals) {
        replaceIfZero(&calcium,    with: other.calcium)
        replaceIfZero(&iron,       with: other.iron)
        replaceIfZero(&magnesium,  with: other.magnesium)
        replaceIfZero(&phosphorus, with: other.phosphorus)
        replaceIfZero(&potassium,  with: other.potassium)
        replaceIfZero(&sodium,     with: other.sodium)
        replaceIfZero(&selenium,   with: other.selenium)
        replaceIfZero(&zinc,       with: other.zinc)
        replaceIfZero(&copper,     with: other.copper)
        replaceIfZero(&manganese,  with: other.manganese)
        replaceIfZero(&fluoride,   with: other.fluoride)
    }
}

@available(iOS 26.0, *)
extension AILipids {
    mutating func merge(from other: AILipids) {
        replaceIfZero(&totalSaturated,       with: other.totalSaturated)
        replaceIfZero(&totalMonounsaturated, with: other.totalMonounsaturated)
        replaceIfZero(&totalPolyunsaturated, with: other.totalPolyunsaturated)
        replaceIfZero(&totalTrans,           with: other.totalTrans)
        replaceIfZero(&totalTransMonoenoic,  with: other.totalTransMonoenoic)
        replaceIfZero(&totalTransPolyenoic,  with: other.totalTransPolyenoic)
        replaceIfZero(&sfa4_0,  with: other.sfa4_0)
        replaceIfZero(&sfa6_0,  with: other.sfa6_0)
        replaceIfZero(&sfa8_0,  with: other.sfa8_0)
        replaceIfZero(&sfa10_0, with: other.sfa10_0)
        replaceIfZero(&sfa12_0, with: other.sfa12_0)
        replaceIfZero(&sfa13_0, with: other.sfa13_0)
        replaceIfZero(&sfa14_0, with: other.sfa14_0)
        replaceIfZero(&sfa15_0, with: other.sfa15_0)
        replaceIfZero(&sfa16_0, with: other.sfa16_0)
        replaceIfZero(&sfa17_0, with: other.sfa17_0)
        replaceIfZero(&sfa18_0, with: other.sfa18_0)
        replaceIfZero(&sfa20_0, with: other.sfa20_0)
        replaceIfZero(&sfa22_0, with: other.sfa22_0)
        replaceIfZero(&sfa24_0, with: other.sfa24_0)
        replaceIfZero(&mufa14_1, with: other.mufa14_1)
        replaceIfZero(&mufa15_1, with: other.mufa15_1)
        replaceIfZero(&mufa16_1, with: other.mufa16_1)
        replaceIfZero(&mufa17_1, with: other.mufa17_1)
        replaceIfZero(&mufa18_1, with: other.mufa18_1)
        replaceIfZero(&mufa20_1, with: other.mufa20_1)
        replaceIfZero(&mufa22_1, with: other.mufa22_1)
        replaceIfZero(&mufa24_1, with: other.mufa24_1)
        replaceIfZero(&tfa16_1_t, with: other.tfa16_1_t)
        replaceIfZero(&tfa18_1_t, with: other.tfa18_1_t)
        replaceIfZero(&tfa22_1_t, with: other.tfa22_1_t)
        replaceIfZero(&tfa18_2_t, with: other.tfa18_2_t)
        replaceIfZero(&pufa18_2, with: other.pufa18_2)
        replaceIfZero(&pufa18_3, with: other.pufa18_3)
        replaceIfZero(&pufa18_4, with: other.pufa18_4)
        replaceIfZero(&pufa20_2, with: other.pufa20_2)
        replaceIfZero(&pufa20_3, with: other.pufa20_3)
        replaceIfZero(&pufa20_4, with: other.pufa20_4)
        replaceIfZero(&pufa20_5, with: other.pufa20_5)
        replaceIfZero(&pufa21_5, with: other.pufa21_5)
        replaceIfZero(&pufa22_4, with: other.pufa22_4)
        replaceIfZero(&pufa22_5, with: other.pufa22_5)
        replaceIfZero(&pufa22_6, with: other.pufa22_6)
        replaceIfZero(&pufa2_4,  with: other.pufa2_4)
    }
}

@available(iOS 26.0, *)
extension AIAminoAcids {
    mutating func merge(from other: AIAminoAcids) {
        replaceIfZero(&alanine,       with: other.alanine)
        replaceIfZero(&arginine,      with: other.arginine)
        replaceIfZero(&asparticAcid,  with: other.asparticAcid)
        replaceIfZero(&cystine,       with: other.cystine)
        replaceIfZero(&glutamicAcid,  with: other.glutamicAcid)
        replaceIfZero(&glycine,       with: other.glycine)
        replaceIfZero(&histidine,     with: other.histidine)
        replaceIfZero(&isoleucine,    with: other.isoleucine)
        replaceIfZero(&leucine,       with: other.leucine)
        replaceIfZero(&lysine,        with: other.lysine)
        replaceIfZero(&methionine,    with: other.methionine)
        replaceIfZero(&phenylalanine, with: other.phenylalanine)
        replaceIfZero(&proline,       with: other.proline)
        replaceIfZero(&threonine,     with: other.threonine)
        replaceIfZero(&tryptophan,    with: other.tryptophan)
        replaceIfZero(&tyrosine,      with: other.tyrosine)
        replaceIfZero(&valine,        with: other.valine)
        replaceIfZero(&serine,        with: other.serine)
        replaceIfZero(&hydroxyproline, with: other.hydroxyproline)
    }
}

@available(iOS 26.0, *)
@Generable
struct AINutrientOnlyResponse: Codable {
    @Guide(description: "A single nutrient value per 100 g with a unit.")
    var nutrient: AINutrient
}

