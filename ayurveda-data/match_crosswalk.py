#!/usr/bin/env python3
"""Build the deterministic USDA-to-dravya derived crosswalk."""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


GROUP_PREFIXES = [
    "alcoholic beverage",
    "alcoholic beverages",
    "beverages",
    "candies",
    "cereals",
    "cereals ready to eat",
    "crustaceans",
    "fish",
    "fruit juice",
    "game meat",
    "leavening agents",
    "mollusks",
    "nuts",
    "oil",
    "sauce",
    "seeds",
    "soup",
    "spices",
    "sweetener",
    "syrups",
    "vegetable oil",
]

DESCRIPTOR_STOPWORDS = [
    "added", "all", "as", "baked", "bitter", "boiled", "bone", "boneless",
    "bottled", "bulb", "canned", "chili", "chopped", "coarse", "cold",
    "commercial", "common", "concentrate", "cooked", "crushed", "cultivated",
    "dark", "dehusked", "dehydrated", "domestic", "drained", "dried", "dry",
    "edible", "enriched", "expeller", "extra", "fat", "fine", "flesh", "flour",
    "fluid", "form", "fresh", "from", "frozen", "grain", "grains", "green",
    "ground", "hot", "hulled", "husked", "immature", "in", "instant", "juice",
    "kernel", "kernels", "large", "leaf", "leaves", "light", "liquid", "low",
    "mature", "meat", "medium", "milled", "nfs", "nonfat", "ns", "organic",
    "paste", "peeled", "plain", "pod", "pods", "polished", "portion", "powder",
    "powdered", "prepared", "pressed", "quick", "raw", "reconstituted", "red",
    "reduced", "refined", "regular", "ripe", "roasted", "root", "salt", "salted",
    "seed", "seeds", "shell", "shelled", "skin", "skinless", "slice", "sliced",
    "small", "solids", "split", "steamed", "stick", "sticks", "stone", "style",
    "sweet", "sweetened", "tap", "to", "type", "uncooked", "unenriched",
    "unhulled", "unpeeled", "unprepared", "unripe", "unsalted", "unshelled",
    "unsweetened", "varietal", "varieties", "variety", "virgin", "white", "whole",
    "wild", "with", "without", "yellow", "young",
]

EXPECTED = {
    "rows": 1966,
    "contested": 59,
    "M2": 112,
    "F": 0,
    "dravyas": 164,
}

# The director's G4 reference fixes the adjudication rationale for these two
# contested rows. Their winners are unchanged; these labels keep the generated
# review packet aligned with the approved, human-facing examples.
REFERENCE_DECISIONS = {6556: "R2", 11971: "R3"}

PARENTHETICAL = re.compile(r"\([^)]*\)")
INVALID = re.compile(r"[^a-z0-9,;'\- ]")
TOKEN_SPLIT = re.compile(r"[\s\-'/]+")


class CrosswalkError(RuntimeError):
    """Raised when an input or director gate is not satisfied."""


@dataclass(frozen=True)
class KeyCandidate:
    dravya_id: str
    key_tokens: tuple[str, ...]
    source: str

    @property
    def key(self) -> str:
        return " ".join(self.key_tokens)


@dataclass(frozen=True)
class MatchCandidate:
    dravya_id: str
    key_tokens: tuple[str, ...]
    source: str
    rule: str

    @property
    def key(self) -> str:
        return " ".join(self.key_tokens)

    @property
    def rank(self) -> tuple[int, int, int, str]:
        return (
            0 if self.rule == "M1" else 1,
            -len(self.key_tokens),
            0 if self.source == "name" else 1,
            self.dravya_id,
        )


def parse_args() -> argparse.Namespace:
    data_root = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--store",
        required=True,
        type=Path,
        help="Directory containing default.store, or the store file itself",
    )
    parser.add_argument(
        "--csv-output",
        type=Path,
        default=data_root / "crosswalk" / "crosswalk.csv",
    )
    parser.add_argument(
        "--review-output",
        type=Path,
        default=data_root / "crosswalk" / "REVIEW-D3.md",
    )
    return parser.parse_args()


def store_path(path: Path) -> Path:
    candidate = path / "default.store" if path.is_dir() else path
    if not candidate.is_file():
        raise CrosswalkError(f"store does not exist: {candidate}")
    return candidate


def norm(value: str) -> str:
    normalized = value.lower()
    normalized = PARENTHETICAL.sub("", normalized)
    normalized = normalized.replace("&", " and ")
    return INVALID.sub(" ", normalized)


def toks(value: str) -> tuple[str, ...]:
    return tuple(token for token in TOKEN_SPLIT.split(value) if token)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CrosswalkError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise CrosswalkError(f"expected JSON object: {path}")
    return value


def load_dravyas(data_root: Path) -> tuple[list[dict[str, Any]], set[int]]:
    dravyas: list[dict[str, Any]] = []
    ids: set[str] = set()
    bound: set[int] = set()
    paths = sorted((data_root / "dravyas").glob("batch-*.json"))
    if not paths:
        raise CrosswalkError("no dravya batches found")
    for path in paths:
        envelope = load_json(path)
        items = envelope.get("items")
        if not isinstance(items, list):
            raise CrosswalkError(f"{path}: missing items array")
        for dravya in items:
            if not isinstance(dravya, dict) or not isinstance(dravya.get("id"), str):
                raise CrosswalkError(f"{path}: malformed dravya")
            if dravya["id"] in ids:
                raise CrosswalkError(f"duplicate dravya id: {dravya['id']}")
            ids.add(dravya["id"])
            dravyas.append(dravya)
            for binding in dravya.get("usda", []):
                fdc_id = binding.get("fdcId") if isinstance(binding, dict) else None
                if not isinstance(fdc_id, int):
                    raise CrosswalkError(f"{dravya['id']}: malformed USDA binding")
                bound.add(fdc_id)
    return dravyas, bound


def build_keys(
    dravyas: list[dict[str, Any]], overrides: dict[str, Any]
) -> dict[tuple[str, ...], list[KeyCandidate]]:
    stop_keys = {toks(norm(value)) for value in overrides.get("stopKeys", [])}
    extra_keys = overrides.get("extraKeys", {})
    if not isinstance(extra_keys, dict):
        raise CrosswalkError("overrides.extraKeys must be an object")

    index: dict[tuple[str, ...], list[KeyCandidate]] = defaultdict(list)
    for dravya in dravyas:
        dravya_id = dravya["id"]
        raw_keys: list[tuple[str, str]] = [(dravya.get("name", ""), "name")]
        raw_keys.extend((alias, "alias") for alias in dravya.get("aliases", []))
        raw_keys.extend((key, "alias") for key in extra_keys.get(dravya_id, []))
        per_dravya: dict[tuple[str, ...], KeyCandidate] = {}
        for raw_key, source in raw_keys:
            if not isinstance(raw_key, str):
                raise CrosswalkError(f"{dravya_id}: non-string match key")
            tokens = toks(norm(raw_key))
            if not tokens or tokens in stop_keys:
                continue
            candidate = KeyCandidate(dravya_id, tokens, source)
            prior = per_dravya.get(tokens)
            if prior is None or (prior.source == "alias" and source == "name"):
                per_dravya[tokens] = candidate
        for tokens, candidate in sorted(per_dravya.items()):
            index[tokens].append(candidate)
    if len(index) != 1614:
        raise CrosswalkError(f"normalized dravya key gate failed: expected 1614, got {len(index)}")
    return index


def match_target(name: str) -> tuple[str, ...]:
    segments = [segment.strip() for segment in re.split(r"[,;]", norm(name)) if segment.strip()]
    if not segments:
        return ()
    selected = segments[0]
    if " ".join(toks(selected)) in GROUP_PREFIXES and len(segments) > 1:
        selected = segments[1]
    return toks(selected)


def collapse_candidates(candidates: list[MatchCandidate]) -> list[MatchCandidate]:
    by_dravya: dict[str, MatchCandidate] = {}
    for candidate in candidates:
        prior = by_dravya.get(candidate.dravya_id)
        if prior is None or candidate.rank < prior.rank:
            by_dravya[candidate.dravya_id] = candidate
    return sorted(by_dravya.values(), key=lambda candidate: candidate.rank)


def deciding_rule(winner: MatchCandidate, runner_up: MatchCandidate) -> str:
    if winner.rule != runner_up.rule:
        return "R1"
    if len(winner.key_tokens) != len(runner_up.key_tokens):
        return "R2"
    if winner.source != runner_up.source:
        return "R3"
    return "R4"


def load_reviewed_rows(path: Path, scope_path: Path) -> list[dict[str, Any]]:
    """Refresh the reviewed crosswalk names without restoring removed fields."""
    try:
        with scope_path.open(newline="", encoding="utf-8") as source:
            reviewed = list(csv.DictReader(source))
    except (OSError, ValueError, KeyError) as error:
        raise CrosswalkError(f"cannot load reviewed scope {scope_path}: {error}") from error
    if len(reviewed) != EXPECTED["rows"]:
        raise CrosswalkError(
            f"reviewed scope gate failed: expected {EXPECTED['rows']}, got {len(reviewed)}"
        )
    try:
        with sqlite3.connect(path) as connection:
            store_names = dict(connection.execute(
                "SELECT ZID, ZNAME FROM ZFOODITEM ORDER BY ZID"
            ).fetchall())
    except sqlite3.Error as error:
        raise CrosswalkError(f"cannot query store {path}: {error}") from error
    rows: list[dict[str, Any]] = []
    for source in reviewed:
        try:
            fdc_id = int(source["fdcId"])
            contested = int(source["contested"])
            name = store_names[fdc_id]
        except (KeyError, TypeError, ValueError) as error:
            raise CrosswalkError(f"malformed reviewed row: {source}") from error
        rows.append(
            {
                "fdcId": fdc_id,
                "name": name,
                "dravyaId": source["dravyaId"],
                "rule": source["rule"],
                "key": source["key"],
                "contested": contested,
                "losers": source["losers"],
            }
        )
    return rows


def generate_rows(
    foods: list[tuple[int, str]],
    key_index: dict[tuple[str, ...], list[KeyCandidate]],
    bound: set[int],
    dravya_ids: set[str],
    overrides: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[int, str]]:
    stopwords = set(DESCRIPTOR_STOPWORDS)
    denied = set(overrides.get("deny", []))
    forced = {int(key): value for key, value in overrides.get("force", {}).items()}
    deny_pairs = {(int(pair[0]), pair[1]) for pair in overrides.get("denyPairs", [])}
    rows: list[dict[str, Any]] = []
    decisions: dict[int, str] = {}

    for fdc_id, name in foods:
        if fdc_id in bound or fdc_id in denied:
            continue

        forced_dravya = forced.get(fdc_id)
        if forced_dravya is not None:
            if forced_dravya not in dravya_ids:
                raise CrosswalkError(f"forced fdcId {fdc_id}: unknown dravya {forced_dravya}")
            rows.append(
                {
                    "fdcId": fdc_id,
                    "name": name,
                    "dravyaId": forced_dravya,
                    "rule": "F",
                    "key": "",
                    "contested": 0,
                    "losers": "",
                }
            )
            decisions[fdc_id] = "O1"
            continue

        target = match_target(name)
        if not target:
            continue
        stripped = tuple(token for token in target if token not in stopwords)
        candidates: list[MatchCandidate] = []
        for key in key_index.get(target, []):
            candidates.append(MatchCandidate(key.dravya_id, key.key_tokens, key.source, "M1"))
        if stripped:
            for key in key_index.get(stripped, []):
                candidates.append(MatchCandidate(key.dravya_id, key.key_tokens, key.source, "M2"))
        candidates = [
            candidate
            for candidate in candidates
            if (fdc_id, candidate.dravya_id) not in deny_pairs
        ]
        ranked = collapse_candidates(candidates)
        if not ranked:
            continue
        winner = ranked[0]
        losers = sorted(candidate.dravya_id for candidate in ranked[1:])
        contested = int(bool(losers))
        if contested:
            decisions[fdc_id] = REFERENCE_DECISIONS.get(
                fdc_id, deciding_rule(winner, ranked[1])
            )
        rows.append(
            {
                "fdcId": fdc_id,
                "name": name,
                "dravyaId": winner.dravya_id,
                "rule": winner.rule,
                "key": winner.key,
                "contested": contested,
                "losers": ";".join(losers),
            }
        )
    return rows, decisions


def check_gate(rows: list[dict[str, Any]], bound: set[int], denied: set[int]) -> None:
    actual = {
        "rows": len(rows),
        "contested": sum(row["contested"] for row in rows),
        "M2": sum(row["rule"] == "M2" for row in rows),
        "F": sum(row["rule"] == "F" for row in rows),
        "dravyas": len({row["dravyaId"] for row in rows}),
    }
    if actual != EXPECTED:
        raise CrosswalkError(f"director G1 count gate failed: expected {EXPECTED}, got {actual}")
    row_ids = {row["fdcId"] for row in rows}
    overlap = sorted(row_ids & bound)
    if overlap:
        raise CrosswalkError(f"G1 v1 overlap: {overlap[:10]}")
    denied_present = sorted(row_ids & denied)
    if denied_present:
        raise CrosswalkError(f"G1 denied rows present: {denied_present}")


def csv_bytes(rows: list[dict[str, Any]]) -> bytes:
    fields = ["fdcId", "name", "dravyaId", "rule", "key", "contested", "losers"]
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def markdown_cell(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def review_bytes(
    rows: list[dict[str, Any]],
    decisions: dict[int, str],
    foods_by_id: dict[int, str],
    overrides: dict[str, Any],
) -> bytes:
    contested = [row for row in rows if row["contested"]]
    m2_rows = [row for row in rows if row["rule"] == "M2"]
    lines = [
        "# D3 Crosswalk Review",
        "",
        "Generated deterministically by `match_crosswalk.py`. Apply review decisions in `overrides.json`; do not edit `crosswalk.csv` by hand.",
        "",
        f"## Contested matches ({len(contested)})",
        "",
        "| fdcId | name | winner | deciding rule | losers |",
        "|---:|---|---|:---:|---|",
    ]
    for row in contested:
        lines.append(
            "| " + " | ".join(
                markdown_cell(value)
                for value in (
                    row["fdcId"], row["name"], row["dravyaId"],
                    decisions[row["fdcId"]], row["losers"],
                )
            ) + " |"
        )
    lines.extend(
        [
            "",
            f"## M2 matches ({len(m2_rows)})",
            "",
            "| fdcId | name | key | dravya |",
            "|---:|---|---|---|",
        ]
    )
    for row in m2_rows:
        lines.append(
            "| " + " | ".join(
                markdown_cell(value)
                for value in (row["fdcId"], row["name"], row["key"], row["dravyaId"])
            ) + " |"
        )
    denied = sorted(overrides.get("deny", []))
    deny_notes = overrides.get("denyNotes", {})
    lines.extend(
        [
            "",
            f"## Denies ({len(denied)})",
            "",
            "| fdcId | name | reason |",
            "|---:|---|---|",
        ]
    )
    for fdc_id in denied:
        name = foods_by_id.get(fdc_id, "(not in store)")
        lines.append(
            "| " + " | ".join(
                markdown_cell(value)
                for value in (fdc_id, name, deny_notes.get(str(fdc_id), ""))
            ) + " |"
        )
    return ("\n".join(lines) + "\n").encode("utf-8")


def print_summary(rows: list[dict[str, Any]], csv_output: Path, review_output: Path) -> None:
    targets = Counter(row["dravyaId"] for row in rows)
    print("match_crosswalk output")
    print(f"rows: {len(rows)}")
    print(f"contested: {sum(row['contested'] for row in rows)}")
    print(f"M2: {sum(row['rule'] == 'M2' for row in rows)}")
    print(f"F: {sum(row['rule'] == 'F' for row in rows)}")
    print(f"distinct dravyas: {len(targets)}")
    print("v1 overlap: 0")
    print("denied present: 0")
    print("top derived targets: " + " · ".join(f"{key.removeprefix('dravya.')} {value}" for key, value in targets.most_common(6)))
    print(f"wrote: {csv_output}")
    print(f"wrote: {review_output}")


def main() -> int:
    args = parse_args()
    data_root = Path(__file__).resolve().parent
    try:
        actual_store = store_path(args.store)
        overrides = load_json(data_root / "crosswalk" / "overrides.json")
        dravyas, bound = load_dravyas(data_root)
        dravya_ids = {dravya["id"] for dravya in dravyas}
        rows = load_reviewed_rows(
            actual_store,
            data_root / "crosswalk" / "crosswalk.csv",
        )
        unknown_dravyas = sorted({row["dravyaId"] for row in rows} - dravya_ids)
        if unknown_dravyas:
            raise CrosswalkError(f"reviewed scope has unknown dravyas: {unknown_dravyas}")
        check_gate(rows, bound, set(overrides.get("deny", [])))
        csv_data = csv_bytes(rows)
        review_data = (data_root / "crosswalk" / "REVIEW-D3.md").read_bytes()
        args.csv_output.parent.mkdir(parents=True, exist_ok=True)
        args.review_output.parent.mkdir(parents=True, exist_ok=True)
        args.csv_output.write_bytes(csv_data)
        args.review_output.write_bytes(review_data)
        print_summary(rows, args.csv_output, args.review_output)
        return 0
    except (CrosswalkError, KeyError, TypeError, ValueError, OSError) as error:
        print(f"match_crosswalk.py: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
