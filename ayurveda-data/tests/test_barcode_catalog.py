import base64
import gzip
import json
import sqlite3
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Ayura" / "Legacy"
sys.path.insert(0, str(ROOT / "ayurveda-data"))
from stable_ids import food_uuid, product_bucket_uuid, vocabulary_entry_uuid


def normalized_decimal(value: str) -> str:
    normalized = value.lstrip("0")
    return normalized or "0"


class PartReader:
    def __init__(self, paths):
        self.paths = iter(paths)
        self.current = None

    def read(self, size=-1):
        chunks = []
        received = 0
        while size < 0 or received < size:
            if self.current is None:
                try:
                    self.current = next(self.paths).open("rb")
                except StopIteration:
                    break
            remaining = -1 if size < 0 else size - received
            chunk = self.current.read(remaining)
            if chunk:
                chunks.append(chunk)
                received += len(chunk)
            else:
                self.current.close()
                self.current = None
        return b"".join(chunks)


class BarcodeCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata = json.loads(
            (CATALOG / "barcode_catalog_metadata.json").read_text(
                encoding="utf-8"
            )
        )
        cls.vocabulary = json.loads(
            (CATALOG / "vocabulary.json").read_text(encoding="utf-8")
        )
        cls.buckets = json.loads(
            (CATALOG / "product_buckets.json").read_text(encoding="utf-8")
        )

    def test_metadata_and_vocabulary_are_consistent(self):
        self.assertEqual(self.metadata["schemaVersion"], 1)
        self.assertEqual(
            len(self.vocabulary),
            self.metadata["vocabularyCount"],
        )
        self.assertEqual(len(self.buckets), self.metadata["bucketCount"])
        self.assertEqual(self.vocabulary[0]["word"], "UNK")
        for index, row in enumerate(self.vocabulary):
            self.assertEqual(row["tokenIndex"], index)
            self.assertEqual(row["id"], vocabulary_entry_uuid(index))

    def test_food_targets_use_the_git_uuid_migration(self):
        foods = json.loads(
            (CATALOG / "foods.json").read_text(encoding="utf-8")
        )
        for food in foods:
            self.assertEqual(
                food["id"],
                food_uuid(food["catalogNumber"]),
            )

    def test_buckets_cover_sorted_unique_product_codes(self):
        vocabulary_count = len(self.vocabulary)
        product_count = 0
        previous_sort_key = None
        previous_bucket_key = None
        for bucket_row in self.buckets:
            bucket_key = normalized_decimal(bucket_row["bucketKey"])
            self.assertEqual(
                bucket_row["id"],
                product_bucket_uuid(int(bucket_key)),
            )
            bucket_sort_key = (len(bucket_key), bucket_key)
            if previous_bucket_key is not None:
                self.assertLess(previous_bucket_key, bucket_sort_key)
            previous_bucket_key = bucket_sort_key

            payload = json.loads(
                zlib.decompress(
                    base64.b64decode(bucket_row["compressedData"])
                )
            )
            self.assertTrue(payload)
            first_code = next(iter(payload))
            self.assertEqual(normalized_decimal(first_code), bucket_key)
            for code, token_ids in payload.items():
                self.assertTrue(code.isdecimal())
                normalized = normalized_decimal(code)
                sort_key = (len(normalized), normalized, code)
                if previous_sort_key is not None:
                    self.assertLess(previous_sort_key, sort_key)
                previous_sort_key = sort_key
                self.assertTrue(token_ids)
                self.assertTrue(
                    all(0 <= token_id < vocabulary_count for token_id in token_ids)
                )
                product_count += 1
        self.assertEqual(product_count, self.metadata["productCount"])

    def test_preseed_contains_the_same_catalog(self):
        parts = sorted((ROOT / "Ayura").glob("preseeded_db.store.gz.part-*"))
        self.assertIn(len(parts), (2, 3))
        with tempfile.NamedTemporaryFile(suffix=".store") as store:
            reader = PartReader(parts)
            with gzip.GzipFile(fileobj=reader, mode="rb") as source:
                while chunk := source.read(1024 * 1024):
                    store.write(chunk)
            store.flush()
            with sqlite3.connect(f"file:{store.name}?mode=ro", uri=True) as connection:
                vocabulary_count = connection.execute(
                    "SELECT count(*) FROM ZVOCABULARYENTRY"
                ).fetchone()[0]
                bucket_count = connection.execute(
                    "SELECT count(*) FROM ZPRODUCTBUCKET"
                ).fetchone()[0]
                integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
                vocabulary_samples = [
                    connection.execute(
                        "SELECT ZTOKENINDEX, ZID FROM ZVOCABULARYENTRY "
                        "ORDER BY Z_PK LIMIT 1 OFFSET ?",
                        (offset,),
                    ).fetchone()
                    for offset in (0, vocabulary_count // 2, vocabulary_count - 1)
                ]
                bucket_samples = [
                    connection.execute(
                        "SELECT ZBUCKETKEY, ZID FROM ZPRODUCTBUCKET "
                        "ORDER BY Z_PK LIMIT 1 OFFSET ?",
                        (offset,),
                    ).fetchone()
                    for offset in (0, bucket_count // 2, bucket_count - 1)
                ]
        self.assertEqual(vocabulary_count, self.metadata["vocabularyCount"])
        self.assertEqual(bucket_count, self.metadata["bucketCount"])
        self.assertEqual(integrity, "ok")
        for token_index, identifier in vocabulary_samples:
            self.assertEqual(
                str(uuid_from_store(identifier)),
                vocabulary_entry_uuid(token_index),
            )
        for bucket_key, identifier in bucket_samples:
            self.assertEqual(
                str(uuid_from_store(identifier)),
                product_bucket_uuid(int(bucket_key)),
            )


def uuid_from_store(value):
    import uuid

    return uuid.UUID(bytes=bytes(value))


if __name__ == "__main__":
    unittest.main()
