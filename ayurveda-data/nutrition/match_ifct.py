import collections
import csv
import glob
import json
import re
import sqlite3
import unicodedata


B = "ayurveda-data/nutrition/"
WITHDRAWN_STATUS = "withdrawn — wrong IFCT row, see TASK-NUT1 §2"


def norm(value):
    value = (
        unicodedata.normalize("NFKD", value or "")
        .encode("ascii", "ignore")
        .decode()
        .lower()
    )
    value = re.sub(r"\([^)]*\)", " ", value)
    value = re.sub(r"[^a-z0-9 ]", " ", value)
    stop = {"raw", "the", "and", "of", "a", "an"}
    tokens = [word for word in value.split() if word and word not in stop]
    return tuple(
        sorted(
            set(
                word[:-1]
                if len(word) > 3 and word.endswith("s") and not word.endswith("ss")
                else word
                for word in tokens
            )
        )
    )


def reverse_collisions(exact):
    by_code = collections.defaultdict(list)
    for match in exact:
        by_code[match[2]].append(match)
    return {code: matches for code, matches in by_code.items() if len(matches) > 1}


def reviewed_withdrawal(review, code):
    return (
        review.get("status") == WITHDRAWN_STATUS
        and review.get("withdrawnIfctCode") == code
    )


def reviewed_active_collision(review, code):
    disposition = review.get("reverseCollision")
    return (
        isinstance(disposition, dict)
        and disposition.get("ifctCode") == code
        and isinstance(disposition.get("status"), str)
        and disposition["status"].startswith("reviewed — ")
    )


rows = list(
    csv.DictReader(
        open(B + "ifct2017-compositions.csv", encoding="utf-8", errors="replace")
    )
)
C = {column.split("; ")[-1]: column for column in rows[0]}

# IFCT keys: English name plus every local-language synonym.
ikeys = collections.defaultdict(list)
for row in rows:
    names = [row[C["name"]]]
    for part in (row[C["lang"]] or "").split(";"):
        part = re.sub(r"^\s*[A-Za-z.]{1,5}\.\s*", "", part.strip())
        if part:
            names.append(part)
    for name in names:
        key = norm(name)
        if key:
            ikeys[key].append(row)

dravyas = {
    item["id"]: item
    for path in glob.glob("ayurveda-data/dravyas/batch-*.json")
    for item in json.load(open(path))["items"]
}
foods = {
    record["dravyaId"]: record
    for record in json.load(open(B + "dravya_foods.json"))
}
connection = sqlite3.connect("/tmp/dbw/db.store")
placeholders = {
    row[0]: row[1]
    for row in connection.execute(
        "select ZFOODID,ZID from ZAYURVEDAPROFILE "
        "where ZKIND='dravya' and ZFOODID>=900000"
    )
}

exact, ambiguous, none = [], [], []
for food_id, dravya_id in sorted(placeholders.items()):
    dravya = dravyas.get(dravya_id, {})
    candidates = {}
    names = [dravya.get("name"), dravya.get("sanskrit")]
    names.extend(dravya.get("aliases") or [])
    for name in names:
        key = norm(name)
        if key and key in ikeys:
            for row in ikeys[key]:
                candidates[row[C["code"]]] = row
    if len(candidates) == 1:
        row = next(iter(candidates.values()))
        exact.append((dravya_id, dravya.get("name"), row[C["code"]], row[C["name"]]))
    elif len(candidates) > 1:
        ambiguous.append(
            (
                dravya_id,
                dravya.get("name"),
                [(row[C["code"]], row[C["name"]]) for row in candidates.values()],
            )
        )
    else:
        none.append((dravya_id, dravya.get("name")))

collisions = reverse_collisions(exact)
unreviewed = {}
withdrawn = []
for code, matches in collisions.items():
    active = []
    for match in matches:
        review = foods.get(match[0], {}).get("_review", {})
        if reviewed_withdrawal(review, code):
            withdrawn.append(match)
        else:
            active.append(match)
    if len(active) > 1 and not all(
        reviewed_active_collision(foods.get(match[0], {}).get("_review", {}), code)
        for match in active
    ):
        unreviewed[code] = matches

withdrawn_ids = {match[0] for match in withdrawn}
active_exact = [match for match in exact if match[0] not in withdrawn_ids]

print(f"IFCT rows {len(rows)}   match keys {len(ikeys)}")
print(f"EXACT single match : {len(exact)}")
print(f"AMBIGUOUS (>1)     : {len(ambiguous)}")
print(f"NO MATCH           : {len(none)}")
print(
    "REVERSE COLLISIONS: "
    f"{len(collisions)} groups / {sum(len(matches) for matches in collisions.values())} dravyas"
)
print(
    "UNREVIEWED REVERSE COLLISIONS: "
    f"{len(unreviewed)} groups / {sum(len(matches) for matches in unreviewed.values())} dravyas"
)
for code, matches in sorted(unreviewed.items()):
    names = ", ".join(f"{match[0]} ({match[1]})" for match in matches)
    print(f"   [{code}] {names}")

if unreviewed:
    raise SystemExit(
        "refusing to write /tmp/match.json: review every reverse collision first"
    )

print("\nsample exact:")
for match in active_exact[:16]:
    print(f"   {match[1][:32]:<32} -> [{match[2]}] {match[3]}")
print("\nsample ambiguous:")
for match in ambiguous[:5]:
    print(f"   {match[1][:30]:<30} -> {[name for _, name in match[2]][:3]}")

json.dump(
    {
        "exact": active_exact,
        "ambiguous": ambiguous,
        "none": none,
        "withdrawn": withdrawn,
    },
    open("/tmp/match.json", "w"),
    indent=1,
    ensure_ascii=False,
)
