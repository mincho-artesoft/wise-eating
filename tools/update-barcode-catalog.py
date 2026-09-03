#!/usr/bin/env python3
"""Rebuild the bundled barcode catalogue from the Open Food Facts TSV export.

Only rows with a non-empty ``product_name`` are included. The runtime lookup
needs a name to reconstruct and map a scanned product to an Ayura ``FoodItem``.
The output format intentionally matches the legacy catalogue:

* a lexicographically indexed, lossless token vocabulary;
* numeric GTIN ordering split into approximately 500-entry buckets; and
* compact JSON payloads compressed with zlib and encoded as Base64.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import email.utils
import gzip
import html
import json
import os
import re
import sqlite3
import sys
import tempfile
import urllib.request
import zlib
from pathlib import Path
from typing import BinaryIO, Iterator


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_URL = (
    "https://static.openfoodfacts.org/data/"
    "en.openfoodfacts.org.products.csv.gz"
)
TOKEN_PATTERN = re.compile(r"[\w']+|[^\w\s']|\s+", re.UNICODE)
BUCKET_SIZE = 500
CATALOG_SCHEMA_VERSION = 1
USER_AGENT = "Ayura-barcode-catalog-builder/1.0"

sys.path.insert(0, str(ROOT / "ayurveda-data"))
from stable_ids import product_bucket_uuid, vocabulary_entry_uuid  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument(
        "--source-url",
        default=DEFAULT_SOURCE_URL,
        help="Open Food Facts .csv.gz export URL",
    )
    source.add_argument(
        "--input",
        type=Path,
        help="Local .csv.gz or uncompressed TSV export",
    )
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=ROOT / "Ayura" / "Legacy",
    )
    parser.add_argument("--bucket-size", type=int, default=BUCKET_SIZE)
    parser.add_argument(
        "--catalog-version",
        type=int,
        help="Monotonic runtime seed version; defaults to source YYYYMMDD",
    )
    return parser.parse_args()


def compact_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def normalized_decimal(code: str) -> str:
    normalized = code.lstrip("0")
    return normalized or "0"


def tokenize(name: str) -> list[str]:
    return TOKEN_PATTERN.findall(name)


def iso_utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def source_date_version(value: str | None) -> int:
    if value:
        try:
            parsed = email.utils.parsedate_to_datetime(value)
            return int(parsed.strftime("%Y%m%d"))
        except (TypeError, ValueError, OverflowError):
            pass
    return int(dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d"))


@contextlib.contextmanager
def open_source(
    *, source_url: str | None, input_path: Path | None
) -> Iterator[tuple[BinaryIO, dict[str, str | None]]]:
    if input_path is not None:
        path = input_path.resolve()
        raw = path.open("rb")
        metadata = {
            "url": None,
            "input": str(path),
            "lastModified": email.utils.formatdate(
                path.stat().st_mtime,
                usegmt=True,
            ),
            "etag": None,
        }
        try:
            if path.suffix == ".gz":
                with gzip.GzipFile(fileobj=raw, mode="rb") as decoded:
                    yield decoded, metadata
            else:
                yield raw, metadata
        finally:
            raw.close()
        return

    assert source_url is not None
    request = urllib.request.Request(
        source_url,
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request) as response:
        metadata = {
            "url": source_url,
            "input": None,
            "lastModified": response.headers.get("Last-Modified"),
            "etag": response.headers.get("ETag"),
        }
        with gzip.GzipFile(fileobj=response, mode="rb") as decoded:
            yield decoded, metadata


def prepare_work_database(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(path)
    connection.execute("PRAGMA journal_mode = OFF")
    connection.execute("PRAGMA synchronous = OFF")
    connection.execute("PRAGMA temp_store = FILE")
    connection.execute(
        """
        CREATE TABLE products (
            code TEXT PRIMARY KEY,
            numeric_length INTEGER NOT NULL,
            numeric_code TEXT NOT NULL,
            product_name TEXT NOT NULL
        ) WITHOUT ROWID
        """
    )
    return connection


def ingest_source(
    connection: sqlite3.Connection,
    source: BinaryIO,
) -> dict[str, int]:
    header_raw = source.readline()
    if not header_raw:
        raise ValueError("Open Food Facts export is empty")
    header = header_raw.decode("utf-8-sig", "replace").rstrip("\r\n").split("\t")
    try:
        code_index = header.index("code")
        name_index = header.index("product_name")
    except ValueError as error:
        raise ValueError("export must contain code and product_name columns") from error
    if code_index != 0:
        raise ValueError(f"expected code to be the first column, got {code_index}")

    batch: list[tuple[str, int, str, str]] = []
    stats = {
        "sourceRows": 0,
        "includedProducts": 0,
        "blankProductNames": 0,
        "invalidCodes": 0,
        "duplicateCodes": 0,
    }

    def insert_batch() -> None:
        if not batch:
            return
        connection.executemany(
            """
            INSERT OR REPLACE INTO products(
                code, numeric_length, numeric_code, product_name
            ) VALUES (?, ?, ?, ?)
            """,
            batch,
        )
        batch.clear()

    for raw_line in source:
        stats["sourceRows"] += 1
        columns = raw_line.decode("utf-8", "replace").rstrip("\r\n").split(
            "\t",
            name_index + 1,
        )
        code = columns[code_index].strip() if columns else ""
        name = columns[name_index].strip() if len(columns) > name_index else ""
        if not code or not code.isdecimal():
            stats["invalidCodes"] += 1
            continue
        if not name:
            stats["blankProductNames"] += 1
            continue

        # OFF occasionally contains HTML entities in names. Preserve the source
        # spelling except for decoding entities that would otherwise be shown to
        # the user literally (for example M&amp;M).
        name = html.unescape(name)
        number = normalized_decimal(code)
        batch.append((code, len(number), number, name))
        stats["includedProducts"] += 1
        if len(batch) >= 10_000:
            insert_batch()
            connection.commit()
        if stats["sourceRows"] % 250_000 == 0:
            print(
                "source progress: "
                f"rows={stats['sourceRows']:,} "
                f"included={stats['includedProducts']:,} "
                f"blank_names={stats['blankProductNames']:,}",
                flush=True,
            )
    insert_batch()
    connection.commit()

    actual_count = connection.execute("SELECT count(*) FROM products").fetchone()[0]
    stats["duplicateCodes"] = stats["includedProducts"] - actual_count
    stats["includedProducts"] = actual_count
    return stats


def collect_tokens(connection: sqlite3.Connection) -> set[str]:
    tokens = {"UNK"}
    for index, (name,) in enumerate(
        connection.execute("SELECT product_name FROM products"),
        start=1,
    ):
        tokens.update(tokenize(name))
        if index % 500_000 == 0:
            print(f"token progress: products={index:,}", flush=True)
    return tokens


def write_vocabulary(
    path: Path,
    tokens: set[str],
) -> tuple[dict[str, int], int]:
    ordered = ["UNK", *sorted(tokens - {"UNK"})]
    token_ids = {token: index for index, token in enumerate(ordered)}
    with path.open("w", encoding="utf-8", newline="") as output:
        output.write("[")
        for index, word in enumerate(ordered):
            if index:
                output.write(",")
            output.write(
                compact_json(
                    {
                        "id": vocabulary_entry_uuid(index),
                        "tokenIndex": index,
                        "word": word,
                    }
                )
            )
        output.write("]")
    return token_ids, len(ordered)


def write_product_buckets(
    path: Path,
    connection: sqlite3.Connection,
    token_ids: dict[str, int],
    bucket_size: int,
) -> tuple[int, int]:
    if bucket_size <= 0:
        raise ValueError("bucket size must be positive")
    query = """
        SELECT code, numeric_code, product_name
        FROM products
        ORDER BY numeric_length, numeric_code, code
    """
    bucket: dict[str, list[int]] = {}
    bucket_numeric_value: str | None = None
    bucket_count = 0
    product_count = 0

    def encoded_bucket() -> str:
        raw = compact_json(bucket).encode("utf-8")
        return base64.b64encode(zlib.compress(raw)).decode("ascii")

    with path.open("w", encoding="utf-8", newline="") as output:
        output.write("[")

        def flush_bucket() -> None:
            nonlocal bucket_count
            if not bucket:
                return
            first_code = next(iter(bucket))
            bucket_key = normalized_decimal(first_code)
            if bucket_count:
                output.write(",")
            output.write(
                compact_json(
                    {
                        "id": product_bucket_uuid(int(bucket_key)),
                        "bucketKey": bucket_key,
                        "compressedData": encoded_bucket(),
                    }
                )
            )
            bucket_count += 1

        for code, numeric_code, name in connection.execute(query):
            if (
                len(bucket) >= bucket_size
                and bucket_numeric_value is not None
                and numeric_code != bucket_numeric_value
            ):
                flush_bucket()
                bucket = {}
            pieces = tokenize(name)
            ids = [token_ids[piece] for piece in pieces]
            if "".join(pieces) != name:
                raise AssertionError(f"lossy tokenization for {code}: {name!r}")
            bucket[code] = ids
            bucket_numeric_value = numeric_code
            product_count += 1
            if product_count % 250_000 == 0:
                print(
                    f"bucket progress: products={product_count:,} "
                    f"buckets={bucket_count:,}",
                    flush=True,
                )
        flush_bucket()
        output.write("]")
    return bucket_count, product_count


def atomic_output_path(target: Path) -> Path:
    return target.with_name(target.name + ".tmp")


def main() -> int:
    args = parse_args()
    output_directory = args.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    vocabulary_target = output_directory / "vocabulary.json"
    buckets_target = output_directory / "product_buckets.json"
    metadata_target = output_directory / "barcode_catalog_metadata.json"
    vocabulary_temporary = atomic_output_path(vocabulary_target)
    buckets_temporary = atomic_output_path(buckets_target)
    metadata_temporary = atomic_output_path(metadata_target)

    for path in (vocabulary_temporary, buckets_temporary, metadata_temporary):
        path.unlink(missing_ok=True)

    try:
        with tempfile.TemporaryDirectory(prefix="ayura-barcodes-") as temporary:
            database_path = Path(temporary) / "products.sqlite"
            connection = prepare_work_database(database_path)
            try:
                with open_source(
                    source_url=None if args.input else args.source_url,
                    input_path=args.input,
                ) as (source, source_metadata):
                    stats = ingest_source(connection, source)
                tokens = collect_tokens(connection)
                print(f"building vocabulary from {len(tokens):,} unique tokens")
                token_ids, vocabulary_count = write_vocabulary(
                    vocabulary_temporary,
                    tokens,
                )
                print("building numerically ordered product buckets")
                bucket_count, product_count = write_product_buckets(
                    buckets_temporary,
                    connection,
                    token_ids,
                    args.bucket_size,
                )
            finally:
                connection.close()

        if product_count != stats["includedProducts"]:
            raise AssertionError(
                f"product count changed: {stats['includedProducts']} -> {product_count}"
            )
        catalog_version = args.catalog_version or source_date_version(
            source_metadata["lastModified"]
        )
        metadata = {
            "schemaVersion": CATALOG_SCHEMA_VERSION,
            "catalogVersion": catalog_version,
            "generatedAt": iso_utc_now(),
            "source": source_metadata,
            "selection": "non-empty product_name",
            "sourceRows": stats["sourceRows"],
            "productCount": product_count,
            "blankProductNameCount": stats["blankProductNames"],
            "invalidCodeCount": stats["invalidCodes"],
            "duplicateCodeCount": stats["duplicateCodes"],
            "vocabularyCount": vocabulary_count,
            "bucketCount": bucket_count,
            "bucketSize": args.bucket_size,
        }
        metadata_temporary.write_text(
            compact_json(metadata),
            encoding="utf-8",
        )
        os.replace(vocabulary_temporary, vocabulary_target)
        os.replace(buckets_temporary, buckets_target)
        os.replace(metadata_temporary, metadata_target)
    except BaseException:
        for path in (vocabulary_temporary, buckets_temporary, metadata_temporary):
            path.unlink(missing_ok=True)
        raise

    print("barcode catalogue updated")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
