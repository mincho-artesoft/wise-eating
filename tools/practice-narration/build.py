#!/usr/bin/env python3
"""Writes narration.en.json and SCRIPT.en.md: the English narration of the 60
practices, cue by cue, with the voice each practice is read in and how that
voice reads. It is what a narration in another language is generated from.

Sources: Ayura/Practices/Data/practices.json (the cues and holds),
Ayura/Practices/Data/voices.json (the six voices and the casting) and
Resources/PracticeNarration/manifest.json (how long each English cue runs).
"""
import json
import pathlib

here = pathlib.Path(__file__).parent
repo = here.parent.parent
practices = json.loads((repo / "Ayura/Practices/Data/practices.json").read_text())
roster = json.loads((repo / "Ayura/Practices/Data/voices.json").read_text())
english = json.loads((repo / "Resources/PracticeNarration/manifest.json").read_text())["practices"]

# Direction that overrides a voice's general delivery, from the recording brief.
NOTES = {
    "descent-into-sleep": "Never rises in pitch or pace. It is meant to be abandoned partway through; "
                          "one energetic lift undoes the descent before it.",
}
KIND_NOTES = {
    "pranayama": "Cautions and counts are read plainly and with authority, not soothingly. "
                 "A safety instruction must not sound optional.",
    "kriya": "Cautions and counts are read plainly and with authority, not soothingly. "
             "A safety instruction must not sound optional.",
}

voices = {}
for v in roster["voices"]:
    voices[v["id"]] = {
        "role": v["role"],
        "who": v["description"].replace(" with a Californian American accent", ""),
        "timbre": v["timbre"], "tone": v["tone"], "power": v["power"],
        "emotion": v["emotion"], "expression": v["expression"], "avoid": v["avoid"],
    }

out = {"wordsPerMinute": 95, "voices": voices, "practices": []}
for p in practices:
    slug = p["slug"]
    cues = []
    for number, cue in enumerate(p["script"]):
        cues.append({"n": number, "text": " ".join(cue["text"].split()), "hold": cue["hold"],
                     "englishSeconds": round(english[slug]["cues"][number]["durationSec"], 1)})
    note = " ".join(x for x in [NOTES.get(slug), KIND_NOTES.get(p["kind"])] if x)
    out["practices"].append({"slug": slug, "title": p["title"], "kind": p["kind"],
                             "voice": roster["cast"][slug], **({"note": note} if note else {}), "cues": cues})
(here / "narration.en.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))

lines = ["# Practice narration — the English script and how it is read", "",
         "Written by `build.py`; do not edit by hand.", "",
         "Every practice is read at about 95 words a minute, which is much slower than ordinary",
         "narration. `hold` is the silence, in seconds, that follows a cue; it is added by the app,",
         "not spoken. The seconds in brackets are how long the English recording of the cue runs.", "",
         "## The six voices", ""]
for name, v in voices.items():
    count = sum(1 for p in out["practices"] if p["voice"] == name)
    lines += [f"### {name.capitalize()} — {v['role']} ({count} practices)", "",
              f"- **Who:** {v['who']}", f"- **Timbre:** {v['timbre']}", f"- **Tone:** {v['tone']}",
              f"- **Power:** {v['power']}", f"- **Emotion:** {v['emotion']}",
              f"- **Expression:** {v['expression']}", f"- **Never:** {v['avoid']}", ""]
lines += ["## The practices", ""]
for p in out["practices"]:
    lines += [f"### {p['title']} (`{p['slug']}`) — {p['kind']}, read by {p['voice'].capitalize()}", ""]
    if p.get("note"):
        lines += [f"> {p['note']}", ""]
    for cue in p["cues"]:
        lines.append(f"{cue['n']:02d}. {cue['text']} _(hold {cue['hold']} s; English {cue['englishSeconds']} s)_")
    lines.append("")
(here / "SCRIPT.en.md").write_text("\n".join(lines))
total = sum(len(c["text"]) for p in out["practices"] for c in p["cues"])
print(len(out["practices"]), "practices,", sum(len(p["cues"]) for p in out["practices"]), "cues,", total, "characters")
