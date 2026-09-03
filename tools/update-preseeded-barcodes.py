#!/usr/bin/env python3
"""Replace barcode tables in the shipped SwiftData preseed and repack it."""

from __future__ import annotations

import argparse
import gzip
import json
import sqlite3
import sys
import tempfile
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ayurveda-data"))

from build_preseeded_store import (  # noqa: E402
    add_estimated_search_fallbacks,
    audit_store,
    compact_store,
    deterministic_gzip,
    write_parts,
)


class PartReader:
    def __init__(self, paths: list[Path]):
        self.paths = iter(paths)
        self.current = None

    def read(self, size: int = -1) -> bytes:
        chunks: list[bytes] = []
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

    def close(self) -> None:
        if self.current is not None:
            self.current.close()
            self.current = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--catalog-directory",
        type=Path,
        default=ROOT / "Ayura" / "Legacy",
    )
    parser.add_argument(
        "--preseed-directory",
        type=Path,
        default=ROOT / "Ayura",
    )
    return parser.parse_args()


def unpack_store(parts: list[Path], destination: Path) -> None:
    reader = PartReader(parts)
    try:
        with gzip.GzipFile(fileobj=reader, mode="rb") as source:
            with destination.open("wb") as output:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
    finally:
        reader.close()


def entity_number(connection: sqlite3.Connection, name: str) -> int:
    row = connection.execute(
        "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = ?",
        (name,),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"preseed has no {name} entity")
    return int(row[0])


def uuid_bytes(value: str) -> bytes:
    return uuid.UUID(value).bytes


def replace_barcode_tables(
    store: Path,
    vocabulary_path: Path,
    buckets_path: Path,
) -> tuple[int, int]:
    vocabulary = json.loads(vocabulary_path.read_text(encoding="utf-8"))
    buckets = json.loads(buckets_path.read_text(encoding="utf-8"))
    with sqlite3.connect(store) as connection:
        vocabulary_entity = entity_number(connection, "VocabularyEntry")
        bucket_entity = entity_number(connection, "ProductBucket")
        connection.execute("PRAGMA foreign_keys = OFF")
        connection.execute("PRAGMA synchronous = OFF")
        with connection:
            connection.execute("DELETE FROM ZVOCABULARYENTRY")
            connection.execute("DELETE FROM ZPRODUCTBUCKET")

            vocabulary_batch = []
            for primary_key, row in enumerate(vocabulary, start=1):
                vocabulary_batch.append(
                    (
                        primary_key,
                        vocabulary_entity,
                        1,
                        row["tokenIndex"],
                        row["word"],
                        sqlite3.Binary(uuid_bytes(row["id"])),
                    )
                )
                if len(vocabulary_batch) >= 10_000:
                    connection.executemany(
                        """
                        INSERT INTO ZVOCABULARYENTRY(
                            Z_PK, Z_ENT, Z_OPT, ZTOKENINDEX, ZWORD, ZID
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        vocabulary_batch,
                    )
                    vocabulary_batch.clear()
            if vocabulary_batch:
                connection.executemany(
                    """
                    INSERT INTO ZVOCABULARYENTRY(
                        Z_PK, Z_ENT, Z_OPT, ZTOKENINDEX, ZWORD, ZID
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    vocabulary_batch,
                )

            bucket_batch = [
                (
                    primary_key,
                    bucket_entity,
                    1,
                    row["bucketKey"],
                    row["compressedData"],
                    sqlite3.Binary(uuid_bytes(row["id"])),
                )
                for primary_key, row in enumerate(buckets, start=1)
            ]
            connection.executemany(
                """
                INSERT INTO ZPRODUCTBUCKET(
                    Z_PK, Z_ENT, Z_OPT, ZBUCKETKEY, ZCOMPRESSEDDATA, ZID
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                bucket_batch,
            )
            connection.execute(
                "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = ?",
                (len(vocabulary), vocabulary_entity),
            )
            connection.execute(
                "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = ?",
                (len(buckets), bucket_entity),
            )

        actual_vocabulary = connection.execute(
            "SELECT count(*) FROM ZVOCABULARYENTRY"
        ).fetchone()[0]
        actual_buckets = connection.execute(
            "SELECT count(*) FROM ZPRODUCTBUCKET"
        ).fetchone()[0]
        if actual_vocabulary != len(vocabulary) or actual_buckets != len(buckets):
            raise RuntimeError(
                "preseed barcode counts do not match generated catalogue: "
                f"vocabulary={actual_vocabulary}/{len(vocabulary)}, "
                f"buckets={actual_buckets}/{len(buckets)}"
            )
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"preseed integrity check failed: {integrity}")
    return len(vocabulary), len(buckets)


def main() -> int:
    args = parse_args()
    catalog_directory = args.catalog_directory.resolve()
    preseed_directory = args.preseed_directory.resolve()
    parts = sorted(preseed_directory.glob("preseeded_db.store.gz.part-*"))
    if len(parts) not in (2, 3):
        raise RuntimeError(f"expected 2 or 3 preseed parts, found {len(parts)}")

    metadata = json.loads(
        (catalog_directory / "barcode_catalog_metadata.json").read_text(
            encoding="utf-8"
        )
    )
    with tempfile.TemporaryDirectory(prefix="ayura-preseed-barcodes-") as temporary:
        temporary_root = Path(temporary)
        source_store = temporary_root / "source.store"
        compacted_store = temporary_root / "compacted.store"
        compressed_store = temporary_root / "preseeded_db.store.gz"
        unpack_store(parts, source_store)
        vocabulary_count, bucket_count = replace_barcode_tables(
            source_store,
            catalog_directory / "vocabulary.json",
            catalog_directory / "product_buckets.json",
        )
        if vocabulary_count != metadata["vocabularyCount"]:
            raise RuntimeError("metadata vocabulary count mismatch")
        if bucket_count != metadata["bucketCount"]:
            raise RuntimeError("metadata bucket count mismatch")

        compact_store(source_store, compacted_store)
        add_estimated_search_fallbacks(compacted_store)
        audit = audit_store(compacted_store)
        deterministic_gzip(compacted_store, compressed_store)
        outputs = write_parts(compressed_store, preseed_directory)

    print("preseed barcode catalogue updated")
    print(f"vocabulary: {vocabulary_count:,}")
    print(f"buckets: {bucket_count:,}")
    for key, value in audit.items():
        print(f"{key}: {value}")
    for path in outputs:
        print(f"wrote: {path} ({path.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
