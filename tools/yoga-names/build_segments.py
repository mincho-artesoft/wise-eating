#!/usr/bin/env python3
"""Writes segments.en.json: everything about a yoga pose that is shown or
searched by name, as one sorted list of distinct strings.

It has the pose titles, their Sanskrit names (so that a language with another
script can give its own spelling: "Тадасана", "ताड़ासन"), and the facet labels
the search also answers to: families, levels and muscle groups. A language is
then a table <language>.json mapping each string to its translation, exactly
as for the food names, packed with:

    tools/food-names/pack.py --catalog yoga <language>
"""
import json
import pathlib

here = pathlib.Path(__file__).parent
asanas = json.loads((here.parent.parent / "ayurveda-data" / "yoga" / "asanas.json").read_text())

strings = set()
for asana in asanas:
    # The app splits a name at ", " like a food name; pose names have none.
    assert ", " not in asana["title"], asana["title"]
    strings.add(asana["title"])
    if asana.get("sanskrit"):
        strings.update(part.strip() for part in asana["sanskrit"].split(", "))
    strings.add(asana["family"])
    strings.update(asana["muscleGroups"])
# The level labels of Ayura/Yoga/Models/YogaSearchIndex.swift, and "Workout".
strings.update(["Beginner", "Intermediate", "Advanced", "Easy", "Level 1", "Level 2", "Level 3", "Workout"])

ordered = sorted(strings, key=lambda s: (s.lower(), s))
(here / "segments.en.json").write_text(json.dumps(ordered, ensure_ascii=False, indent=0))
print(len(ordered), "segments,", sum(len(s) for s in ordered), "characters")
