# Translating yoga names

`work/batch-0.json` and `work/batch-1.json` hold the 1,827 strings of
`segments.en.json`. Each item has `i` (its number), `k` (what it is), `s` (the
string to translate) and, for poses, `in` (the other name of the same pose —
context only, never translate it).

Write `work/<language>/out-N.json`: a JSON array of strings, the same length
and order as `batch-N.json`, one translation per item and nothing else.

## By kind

- `pose` — the English title of a pose ("Mountain Pose", "Warrior II with
  Block", "Seated Cat-Cow with Block"). Write it as a yoga teacher of the
  target language says it in class. Where the language's teachers simply use
  the Sanskrit name and no native title exists, transliterate the English
  title's Sanskrit equivalent rather than inventing a literal one.
- `sanskrit` — the Sanskrit name ("Tadasana", "Adho Mukha Svanasana (wall)").
  Never translate it. Latin-script languages: leave it exactly as it is and
  translate only the note in brackets. Other scripts: respell it the way that
  language's yoga books do ("Тадасана", "ताड़ासन", "タダーサナ", "تاداسانا")
  and translate the note in brackets. For Hindi, Marathi, Gujarati, Bengali
  and the other Indian languages use the real spelling of the Sanskrit word,
  not a respelling of the English letters.
- `family` — the 18 groups poses are filed under ("Backbend", "Forward Fold",
  "Arm Balance"). One or two words, as a filter label.
- `muscle_group` — "Legs", "Core", "Full Body". The everyday word, not the
  anatomical Latin.
- `level` — "Beginner", "Level 1", "Workout". Keep the digit.

## Rules

- The same prop or variation is the same word everywhere: decide once how
  "with Block", "with Strap", "with Chair", "at the Wall", "with Bolster",
  "Supported", "Reclined", "Revolved", "Bound", "Half", "Extended",
  "One-Legged" are said, and keep to it across all 908 poses. The bracket
  notes of the Sanskrit names ("(block)", "(wall)", "(strap)") use the same
  words.
- Keep Roman numerals and digits as they are ("Warrior II", "Level 2").
- Capitalise as the target language does in a list of names. No full stop.
- Whatever a family, level or muscle group is translated to is also what the
  search finds it by, so use the word a person would type.
- These are names of body positions, not descriptions: "Corpse Pose",
  "Happy Baby", "Cow Face Pose" are established names; use the established
  one in the target language even when it sounds odd.

## Mistakes to avoid

- "Pose" is the yoga posture word of the target language, the same one every
  time — not "position" in one place and "posture" or "asana" in another.
- "Fold" is bending the body forward, not folding paper. "Bind" is clasping
  the hands around the body. "Twist" is rotating the spine. "Lock" (bandha)
  is a held muscular contraction. "Flow" is moving from pose to pose.
- "Plank", "Bridge", "Boat", "Plough", "Wheel", "Crow", "Pigeon", "Cobra",
  "Camel", "Eagle", "Tree", "Chair" are pose names; translate the animal or
  object only if that is how the pose is called in the target language.
- "Block", "strap", "bolster", "blanket", "wall", "chair" are yoga props.
