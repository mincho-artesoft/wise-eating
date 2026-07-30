#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/Ayura/Food/assets-manifest.json"

if [[ ! -f "$MANIFEST" ]]; then
    echo "MISSING: Ayura/Food/assets-manifest.json" >&2
    exit 1
fi

PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(command -v python3 || true)"
fi
if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
    echo "ERROR: python3 is required to verify required assets" >&2
    exit 1
fi

"$PYTHON_BIN" - "$REPO_ROOT" "$MANIFEST" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
assets = manifest.get("assets", [])
errors = []
verified = 0
ffprobe = shutil.which("ffprobe")

for entry in assets:
    relative = entry["filename"]
    path = repo / relative
    if not path.is_file():
        errors.append(f"MISSING: {relative}")
        continue

    actual_size = path.stat().st_size
    expected_size = entry["byteSize"]
    if actual_size != expected_size:
        errors.append(
            f"SIZE MISMATCH: {relative} "
            f"(expected {expected_size}, found {actual_size})"
        )

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    actual_sha = digest.hexdigest()
    expected_sha = entry["sha256"]
    if actual_sha != expected_sha:
        errors.append(
            f"SHA256 MISMATCH: {relative} "
            f"(expected {expected_sha}, found {actual_sha})"
        )

    expected_frames = entry.get("frameCount")
    if expected_frames is not None and ffprobe:
        result = subprocess.run(
            [
                ffprobe,
                "-v",
                "error",
                "-count_frames",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=nb_read_frames",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(path),
            ],
            capture_output=True,
            text=True,
        )
        try:
            actual_frames = int(result.stdout.strip())
        except ValueError:
            actual_frames = None
        if result.returncode != 0 or actual_frames != expected_frames:
            errors.append(
                f"FRAME COUNT MISMATCH: {relative} "
                f"(expected {expected_frames}, found {actual_frames})"
            )

    producing_commit = entry.get("producingCommit")
    if (
        producing_commit
        and (repo / ".git").exists()
        and not os.environ.get("XCODE_VERSION_ACTUAL")
    ):
        result = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "-e", f"{producing_commit}^{{commit}}"],
            capture_output=True,
        )
        if result.returncode != 0:
            errors.append(
                f"COMMIT MISSING: {relative} "
                f"(producing commit {producing_commit} does not resolve)"
            )

    if not any(relative in error for error in errors):
        verified += 1

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    print(
        f"required asset verification failed: {len(errors)} problem(s)",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(f"required assets verified: {verified}/{len(assets)}")
if any(entry.get("frameCount") is not None for entry in assets) and not ffprobe:
    print("note: ffprobe unavailable; matching SHA-256 authenticates video frame content")
PY
