#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
MAX_GIT_FILE_BYTES=100000000
SOURCES=(
    "$REPOSITORY_ROOT/Ayura/Legacy/foods.json"
    "$REPOSITORY_ROOT/Ayura/Legacy/product_buckets.json"
    "$REPOSITORY_ROOT/Ayura/Legacy/vocabulary.json"
    "$REPOSITORY_ROOT/ayurveda-data/yoga/sequences.json"
)

for source_path in "${SOURCES[@]}"; do
    if [[ ! -f "$source_path" ]]; then
        echo "MISSING: ${source_path#"$REPOSITORY_ROOT/"}" >&2
        exit 1
    fi

    archive_path="$source_path.gz"
    /usr/bin/gzip -9 -n -f -k "$source_path"
    /usr/bin/gzip -t "$archive_path"

    archive_size="$(stat -f %z "$archive_path")"
    if (( archive_size >= MAX_GIT_FILE_BYTES )); then
        echo "ERROR: ${archive_path#"$REPOSITORY_ROOT/"} is $archive_size bytes" >&2
        exit 1
    fi

    if ! cmp -s "$source_path" <(/usr/bin/gzip -dc "$archive_path"); then
        echo "ERROR: gzip round-trip mismatch for ${source_path#"$REPOSITORY_ROOT/"}" >&2
        exit 1
    fi

    echo "compressed ${source_path#"$REPOSITORY_ROOT/"} -> $archive_size bytes"
done
