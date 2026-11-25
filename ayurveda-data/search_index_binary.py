#!/usr/bin/env python3
"""The binary search index stored in SearchIndexCache.payloadData.

This is the Python twin of Ayura/FoodSearch/SearchIndexBinary.swift; the two
must change together. A payload is handled here as the same dictionary the old
JSON payload decoded to, so the audits and tests read it the way they always
did:

    {"compactFoods": [...], "invertedIndex": {token: [uuid, ...]},
     "vocabulary": [...], "maxNutrientValues": {...},
     "nutrientRankings": {nutrient: [uuid, ...]},
     "ayurvedaFacetIndex": {facet: [uuid, ...]}}

Layout: the bytes "AYSI", one format-version byte, then a raw-DEFLATE stream
holding a string table followed by the body. Integers are LEB128 varints,
numbers are little-endian IEEE doubles, a string is its position in the table,
and a food is its position in the food list.
"""

from __future__ import annotations

import json
import struct
import uuid
import zlib

MAGIC = b"AYSI"
FORMAT_VERSION = 1


class SearchIndexError(ValueError):
    """Raised when a payload cannot be encoded or decoded."""


def is_binary(data: bytes) -> bool:
    return bytes(data[:4]) == MAGIC


def load_payload(data) -> dict:
    """Decode a cache payload, binary or the older JSON form."""
    if isinstance(data, str):
        return json.loads(data)
    data = bytes(data)
    return decode(data) if is_binary(data) else json.loads(data)


class _Writer:
    def __init__(self) -> None:
        self.out = bytearray()
        self.strings: list[str] = []
        self.positions: dict[str, int] = {}

    def varint(self, value: int) -> None:
        if value < 0:
            raise SearchIndexError("negative integer")
        while value >= 0x80:
            self.out.append((value & 0x7F) | 0x80)
            value >>= 7
        self.out.append(value)

    def double(self, value) -> None:
        self.out += struct.pack("<d", float(value))

    def string(self, value: str) -> None:
        position = self.positions.get(value)
        if position is None:
            position = len(self.strings)
            self.positions[value] = position
            self.strings.append(value)
        self.varint(position)

    def string_set(self, values) -> None:
        unique = sorted(set(values))
        self.varint(len(unique))
        for value in unique:
            self.string(value)


def encode(payload: dict) -> bytes:
    writer = _Writer()
    foods = payload["compactFoods"]

    metadata_position: dict[str, int] = {}
    metadata_list: list[dict] = []
    for food in foods:
        metadata = food.get("ayurvedaMetadata")
        if metadata is None:
            continue
        key = json.dumps(metadata, sort_keys=True, ensure_ascii=False)
        if key not in metadata_position:
            metadata_position[key] = len(metadata_list)
            metadata_list.append(metadata)
    metadata_json = json.dumps(
        metadata_list, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    writer.varint(len(metadata_json))
    writer.out += metadata_json

    ordinal: dict[str, int] = {}
    writer.varint(len(foods))
    for position, food in enumerate(foods):
        food_id = uuid.UUID(str(food["id"]))
        ordinal[str(food_id)] = position
        writer.out += food_id.bytes
        writer.string(food["name"])
        writer.string_set(food["searchTokens"])
        writer.varint(int(food["minAgeMonths"]))
        enforced = food.get("enforcedMinAgeMonths")
        writer.varint(0 if enforced is None else int(enforced) + 1)
        writer.string_set(food["allergens"])
        writer.double(food["ph"])
        writer.double(food["referenceWeightG"])
        writer.out.append(
            (1 if food["isRecipe"] else 0)
            | (2 if food["isMenu"] else 0)
            | (4 if food["isFavorite"] else 0)
            | (8 if food["isEdible"] else 0)
        )
        writer.string_set(food["ayurvedaFacets"])
        metadata = food.get("ayurvedaMetadata")
        if metadata is None:
            writer.varint(0)
        else:
            key = json.dumps(metadata, sort_keys=True, ensure_ascii=False)
            writer.varint(metadata_position[key] + 1)
        nutrients = food["nutrientValues"]
        writer.varint(len(nutrients))
        for name in sorted(nutrients):
            writer.string(name)
            writer.double(nutrients[name])
    if len(ordinal) != len(foods):
        raise SearchIndexError("duplicate food id")

    def position_of(food_id) -> int:
        try:
            return ordinal[str(uuid.UUID(str(food_id)))]
        except KeyError:
            raise SearchIndexError("index refers to an unknown food") from None

    def postings(index: dict) -> None:
        writer.varint(len(index))
        for key in sorted(index):
            writer.string(key)
            positions = sorted({position_of(food_id) for food_id in index[key]})
            writer.varint(len(positions))
            previous = 0
            for position in positions:
                writer.varint(position - previous)
                previous = position

    postings(payload["invertedIndex"])
    postings(payload["ayurvedaFacetIndex"])

    writer.varint(len(payload["vocabulary"]))
    for word in payload["vocabulary"]:
        writer.string(word)

    maximums = payload["maxNutrientValues"]
    writer.varint(len(maximums))
    for name in sorted(maximums):
        writer.string(name)
        writer.double(maximums[name])

    rankings = payload["nutrientRankings"]
    writer.varint(len(rankings))
    for name in sorted(rankings):
        writer.string(name)
        writer.varint(len(rankings[name]))
        for food_id in rankings[name]:
            writer.varint(position_of(food_id))

    table = _Writer()
    table.varint(len(writer.strings))
    for value in writer.strings:
        utf8 = value.encode("utf-8")
        table.varint(len(utf8))
        table.out += utf8

    # Fixed settings and no header, so the same payload gives the same bytes.
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = compressor.compress(bytes(table.out + writer.out)) + compressor.flush()
    return MAGIC + bytes([FORMAT_VERSION]) + packed


class _Reader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0

    def take(self, count: int) -> bytes:
        end = self.offset + count
        if count < 0 or end > len(self.data):
            raise SearchIndexError("truncated payload")
        chunk = self.data[self.offset:end]
        self.offset = end
        return chunk

    def varint(self) -> int:
        value = 0
        shift = 0
        while True:
            if self.offset >= len(self.data):
                raise SearchIndexError("truncated payload")
            byte = self.data[self.offset]
            self.offset += 1
            value |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return value
            shift += 7

    def double(self) -> float:
        return struct.unpack("<d", self.take(8))[0]


def decode(data: bytes) -> dict:
    data = bytes(data)
    if not is_binary(data):
        raise SearchIndexError("not a binary search index")
    if data[4] != FORMAT_VERSION:
        raise SearchIndexError(f"unsupported format version {data[4]}")
    reader = _Reader(zlib.decompress(data[5:], -15))

    strings = [
        reader.take(reader.varint()).decode("utf-8")
        for _ in range(reader.varint())
    ]

    def string() -> str:
        return strings[reader.varint()]

    def string_list() -> list[str]:
        return [string() for _ in range(reader.varint())]

    metadata_list = json.loads(reader.take(reader.varint()))

    foods = []
    ids: list[str] = []
    for _ in range(reader.varint()):
        food_id = str(uuid.UUID(bytes=reader.take(16)))
        ids.append(food_id)
        food = {"id": food_id, "name": string(), "searchTokens": string_list()}
        food["minAgeMonths"] = reader.varint()
        enforced = reader.varint()
        if enforced:
            food["enforcedMinAgeMonths"] = enforced - 1
        food["allergens"] = string_list()
        food["ph"] = reader.double()
        food["referenceWeightG"] = reader.double()
        flags = reader.take(1)[0]
        food["isRecipe"] = bool(flags & 1)
        food["isMenu"] = bool(flags & 2)
        food["isFavorite"] = bool(flags & 4)
        food["isEdible"] = bool(flags & 8)
        food["ayurvedaFacets"] = string_list()
        metadata_ref = reader.varint()
        if metadata_ref:
            # A copy, so that editing one food's metadata cannot touch another's.
            food["ayurvedaMetadata"] = json.loads(json.dumps(metadata_list[metadata_ref - 1]))
        nutrients = {}
        for _ in range(reader.varint()):
            name = string()
            nutrients[name] = reader.double()
        food["nutrientValues"] = nutrients
        foods.append(food)

    def postings() -> dict:
        index = {}
        for _ in range(reader.varint()):
            key = string()
            position = 0
            members = []
            for _ in range(reader.varint()):
                position += reader.varint()
                members.append(ids[position])
            index[key] = members
        return index

    inverted = postings()
    facet_index = postings()
    vocabulary = string_list()
    maximums = {}
    for _ in range(reader.varint()):
        name = string()
        maximums[name] = reader.double()
    rankings = {}
    for _ in range(reader.varint()):
        name = string()
        rankings[name] = [ids[reader.varint()] for _ in range(reader.varint())]
    if reader.offset != len(reader.data):
        raise SearchIndexError("trailing bytes")

    return {
        "compactFoods": foods,
        "invertedIndex": inverted,
        "vocabulary": vocabulary,
        "maxNutrientValues": maximums,
        "nutrientRankings": rankings,
        "ayurvedaFacetIndex": facet_index,
    }
