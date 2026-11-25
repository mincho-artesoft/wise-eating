#!/usr/bin/env python3
"""Writes golden_queries.json, the query set for Tests/FoodSearch.

Each query has a category and, where the right answer is not a matter of taste,
an expectation that compare.py checks:
  topAll   all these words appear together in one of the first ten names
  noPh     the query must not turn into a pH filter
  noGoals  the query must not turn into a nutrient filter
  goals    these nutrients must be filtered or ranked on; "sodium:low" also
           fixes the direction, and fails if the same nutrient goes both ways
  ph       the query must turn into a pH filter
  minTotal at least this many foods must come back
Queries with no expectation are still recorded in the baseline snapshot.

Pass a file with one catalogue food name per line to check that every topAll
expectation can be met by some food:  build_queries.py names.txt
"""
import json
import re
import sys

Q = []


def add(cat, q, **expect):
    Q.append({"q": q, "cat": cat, **({"expect": expect} if expect else {})})


def names(cat, *queries, strict=True):
    """Food names: the words must come back. With strict, no filter may be
    invented either; without it a filter that the name itself states ("low
    fat yogurt") is accepted as long as the food is found."""
    for q in queries:
        expect = {"topAll": q.replace("-", " ").split()}
        if strict:
            expect.update(noPh=True, noGoals=True)
        add(cat, q, **expect)


# Ordinary names with no command word in them.
names("name",
      "banana", "apple", "broccoli", "salmon", "olive oil", "ghee", "rice",
      "chicken breast", "ground beef", "cheddar cheese", "whole milk", "egg",
      "oatmeal", "lentils", "chickpeas", "spinach", "carrots", "sweet potato",
      "peanut butter", "orange juice", "greek yogurt", "almonds", "walnuts",
      "tofu", "quinoa", "avocado", "blueberries", "strawberries", "tomato",
      "cucumber", "garlic", "ginger", "turmeric", "cumin", "basmati rice",
      "mung beans", "coconut milk", "honey", "dates", "pumpkin", "zucchini",
      "mushrooms", "bread", "pasta", "butter", "yogurt", "turkey", "pork chop",
      "tuna", "shrimp", "lamb", "kale", "cauliflower", "beets", "mango",
      "pineapple", "papaya", "sesame seeds", "barley", "millet")

# Names that contain a nutrient word.
names("name-nutrient",
      "water chestnuts", "coconut water", "barley water",
      "brown sugar", "palm sugar", "rock sugar", "energy drink", "energy balls",
      "protein powder", "soy protein", "corn starch", "tapioca starch",
      "salt pork", "salted butter", "sea salt", "table salt",
      "sugar cookies", "sugar apple", "watermelon", "watercress",
      "tuna in water", "beef fat", "chicken fat", "powdered sugar",
      "cane sugar", "maple sugar", "water bottled", "tonic water",
      "protein fortified spaghetti", "calcium fortified", "starch jelly")
names("name-nutrient",
      "fat free milk", "high protein bread", "high fiber bread",
      "sugar free energy drink", "high fructose corn syrup",
      "lactose free milk", strict=False)

# Names that contain a pH word.
names("name-ph",
      "sour cream", "sour cherries", "sour dough", "sweet and sour pork",
      "sweet and sour sauce", "sour pickles", "ascorbic acid", "acid wash",
      "lauric acid", "sour cream dressing", "hot and sour soup")

# Names that contain a negation word.
names("name-negation",
      "jellies no sugar", "cocoa no sugar added", "without skin",
      "non-dairy", "non-fat yogurt",
      "gluten-free bread", "fat free dressing", "free range", "non-chocolate",
      "not fortified", "caffeine free soft drink", "milk-fat free",
      "without ascorbic acid", "excluding", strict=False)

# Names that contain a comparison word.
names("name-operator",
      "great northern beans", "small end rib", "under blade", "light beer",
      "light mayonnaise", "light tuna", "small patty", "extra light syrup")
names("name-operator",
      "low fat yogurt", "low sodium pickles", "high oleic sunflower oil",
      "equal volume water", "low calorie cola", "reduced sugar cola",
      "low fat cottage cheese", strict=False)


def command(q, goals=(), ph=False):
    expect = {"minTotal": 1}
    if goals:
        expect["goals"] = list(goals)
    if ph:
        expect["ph"] = True
    add("command", q, **expect)


# Real commands: these must keep working exactly as they do now.
for q, g in [
    ("high protein", ["protein:high"]), ("low fat", ["totalFat:low"]),
    ("low sodium", ["sodium:low"]), ("high fiber", ["fiber:high"]),
    ("low sugar", ["totalSugar:low"]), ("sugar free", ["totalSugar:low"]),
    ("fat free", ["totalFat:low"]), ("low carb", ["carbs:low"]),
    ("protein > 20", ["protein:high"]), ("protein more than 20", ["protein:high"]),
    ("protein at least 15 g", ["protein:high"]), ("fat < 5", ["totalFat:low"]),
    ("fat less than 3", ["totalFat:low"]), ("calories under 100", ["energy:low"]),
    ("less than 100 calories", ["energy:low"]), ("vitamin c > 50", ["vitaminC:high"]),
    ("high vitamin c", ["vitaminC:high"]), ("vitamin b12", ["vitaminB12"]),
    ("high iron", ["iron:high"]), ("iron more than 5 mg", ["iron:high"]),
    ("calcium at least 200 mg", ["calcium:high"]), ("high calcium", ["calcium:high"]),
    ("potassium > 400", ["potassium:high"]), ("high potassium", ["potassium"]),
    ("zero cholesterol", ["cholesterol:low"]), ("no cholesterol", ["cholesterol:low"]),
    ("high fiber low sugar", ["fiber:high", "totalSugar:low"]),
    ("high protein low fat", ["protein:high", "totalFat:low"]),
    ("protein between 10 and 20", ["protein"]), ("magnesium", ["magnesium"]),
    ("zinc", ["zinc"]), ("folate", ["folateTotal"]), ("omega 3", []),
    ("high vitamin d", ["vitaminD"]), ("vitamin a", ["vitaminA"]),
    ("sodium < 140 mg", ["sodium:low"]),
    ("no salt added", ["sodium:low"]), ("without salt", ["sodium:low"]),
    ("caffeine free", ["caffeine:low"]), ("lower sodium", ["sodium:low"]),
    ("high caffeine", ["caffeine:high"]), ("caffeine", ["caffeine"]),
    ("lactose free", ["lactose:low"]), ("without lactose", ["lactose:low"]),
    ("protein 20", ["protein"]), ("carbs <= 10", ["carbs:low"]),
    ("fiber >= 5", ["fiber:high"]), ("high selenium", ["selenium"]),
]:
    command(q, goals=g)
for q in ["ph < 5", "ph > 7", "ph 7", "ph between 6 and 7", "alkaline",
          "acidic", "neutral ph", "low ph", "high ph", "low acid",
          "alkaline food", "acidic food", "most alkaline", "ph less than 4"]:
    command(q, ph=True)
add("command", "ph")  # shows the pH column; it is not a filter
for q in ["no gluten", "without nuts", "no dairy", "egg free", "no allergens",
          "for 8 months", "safe for 2 year old", "12 months", "no peanuts"]:
    add("command", q)

# A food word together with a command.
for q, words, goals, ph in [
    ("chicken high protein", ["chicken"], ["protein:high"], False),
    ("cheese low fat", ["cheese"], ["totalFat:low"], False),
    ("bread low sodium", ["bread"], ["sodium:low"], False),
    ("yogurt protein > 8", ["yogurt"], ["protein:high"], False),
    ("fruit high vitamin c", [], ["vitaminC"], False),
    ("beans high fiber", ["beans"], ["fiber:high"], False),
    ("fish low fat", ["fish"], ["totalFat:low"], False),
    ("cereal high iron", ["cereal"], ["iron"], False),
    ("milk high calcium", ["milk"], ["calcium:high"], False),
    ("juice low sugar", ["juice"], ["totalSugar:low"], False),
    ("soup sodium < 300", ["soup"], ["sodium:low"], False),
    ("nuts high magnesium", ["nuts"], ["magnesium"], False),
    ("alkaline vegetables", [], [], True),
    ("acidic fruit", [], [], True),
    ("cheese ph < 6", ["cheese"], [], True),
    ("rice without salt", ["rice"], ["sodium:low"], False),
    ("chicken no skin", ["chicken"], [], False),
    ("chicken without skin", ["chicken"], [], False),
    ("milk without lactose", ["milk"], ["lactose:low"], False),
    ("beef protein more than 25", ["beef"], ["protein:high"], False),
    ("snack less than 150 calories", [], ["energy:low"], False),
]:
    expect = {"minTotal": 1}
    if words:
        expect["topAll"] = words
    if goals:
        expect["goals"] = goals
    if ph:
        expect["ph"] = True
    add("mixed", q, **expect)

# Ayurveda vocabulary: recorded, not judged.
for q in ["vata pacifying", "pitta pacifying", "kapha reducing", "heating",
          "cooling", "sweet taste", "bitter", "astringent", "pungent",
          "light and dry", "heavy", "easy to digest", "kindles agni",
          "good for vata", "aggravates pitta", "winter foods", "summer",
          "warming breakfast", "kitchari", "dal", "chai", "lassi", "khichdi",
          "ashwagandha", "triphala"]:
    add("ayurveda", q)

# Typing as people type: prefixes, typos, slang.
for q in ["chiken", "brocoli", "tomatos", "yoghurt", "avo", "oj", "spuds",
          "chick", "bana", "straw", "chees", "choclate", "spagetti", "veggies",
          "pb", "fries", "coke", "brew", "bluberry", "letuce", "cinamon",
          "yog", "sal", "app", "mush"]:
    add("typing", q)

# Other languages and scripts: recorded now, judged from the locale phase on.
for q in ["пиле", "мляко", "ябълка", "ориз", "кисело мляко", "pollo", "leche",
          "manzana", "Hähnchen", "Milch", "Äpfel", "poulet", "lait", "pomme",
          "苹果", "牛奶", "りんご", "牛乳", "दूध", "चावल", "تفاح", "사과",
          "яблоко", "молоко"]:
    add("locale", q)

# Odd input.
for q in ["", " ", "%", "2% milk", "1% milk", "100% juice", "7 up", "v8",
          "half and half", "b12", "c", "a", "m&m", "3 musketeers", "🍎",
          "chicken, breast, raw", "CHICKEN BREAST", "  chicken   breast  ",
          "chicken breast grilled without skin low sodium high protein",
          "or", "and", "high", "low", "free", "no", ">", "< 5", "20"]:
    add("edge", q)

seen = set()
for entry in Q:
    key = (entry["q"], entry["cat"])
    assert key not in seen, key
    seen.add(key)

if len(sys.argv) > 1:
    catalogue = [set(re.findall(r"[a-z0-9]+", line.lower())) for line in open(sys.argv[1])]

    def stems(word):
        return {word, word.rstrip("s"), word + "s", word[:-2] if word.endswith("es") else word}

    for entry in Q:
        words = entry.get("expect", {}).get("topAll")
        if words and not any(all(stems(w.lower()) & tokens for w in words) for tokens in catalogue):
            print("no food can satisfy:", entry["q"])

json.dump(Q, open("golden_queries.json", "w"), ensure_ascii=False, indent=1)
print(len(Q), "queries")
