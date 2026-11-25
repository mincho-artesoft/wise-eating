# Yoga names in other languages

The yoga catalogue is translated and searched the same way as the food names
(`tools/food-names`), with the same file format and the same packing tool.

- `segments.en.json` — the 1,827 strings to translate, written by
  `build_segments.py` from `ayurveda-data/yoga/asanas.json`: the 908 pose
  titles, their Sanskrit names, and the labels the search also answers to
  (18 families, 19 muscle groups, the level words). Re-run the script when the
  catalogue changes.
- `<language>.json` — one table per language, `{ "English string":
  "translation" }`, exactly like `tools/food-names/<language>.json`. A string
  left out or mapped to itself stays English in the app.
- `python3 tools/food-names/pack.py --catalog yoga <language> …` checks a
  table and writes `Ayura/Yoga/Names/yoga_names.<language>.z`. Nothing else
  has to change: the app picks the file up by language, and the test
  `testYogaSearch` and the golden run (`tools/search-golden/remote.sh run`)
  cover the search.

What to translate, and how:

- Pose titles ("Mountain Pose", "Warrior II with Block") are translated as a
  yoga teacher of that language would say them.
- Sanskrit names ("Tadasana", "Adho Mukha Svanasana (wall)") are not
  translated: they are respelled in the language's script when it is not
  Latin ("Тадасана", "ताड़ासन", "タダーサナ"), and left as they are for
  Latin-script languages. Translate only the note in brackets ("wall",
  "chair", "strap").
- A catalogue pose is stored as "Mountain Pose (Tadasana)". The app takes the
  title and the Sanskrit name apart, translates each, and puts them back in
  the same shape, so translate them as separate strings — they already are
  separate in `segments.en.json`.
- Family, level and muscle-group labels are single entries; whatever they are
  translated to is also what the search finds them by in that language.

English and Sanskrit names keep working in every language: the index holds
them beside the translated names.
