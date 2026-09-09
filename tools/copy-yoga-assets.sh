#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
YOGA_SOURCE_DIRECTORY="$REPOSITORY_ROOT/Ayura/Yoga"
YOGA_DESTINATION_DIRECTORY="${1:?destination Yoga resource directory is required}"
YOGA_ASSETS=(
    assets-manifest.json
    frame_index.json
    frame_timestamps.json
    yoga_archive_144.mp4
    yoga_archive_480.mp4
    yoga_archive_1024.mp4
)

/bin/mkdir -p "$YOGA_DESTINATION_DIRECTORY"
for asset in "${YOGA_ASSETS[@]}"; do
    source_path="$YOGA_SOURCE_DIRECTORY/$asset"
    if [[ ! -f "$source_path" ]]; then
        echo "MISSING Yoga bundle asset: $source_path" >&2
        exit 1
    fi
    # NOT ditto. ENABLE_USER_SCRIPT_SANDBOXING = YES restricts writes to the
    # paths declared in this phase's outputPaths. ditto writes a randomly-named
    # temp file (.BC.T_xxxxxx) and renames it into place; that name can never be
    # declared, so the sandbox denies it and the build fails. cp writes straight
    # to the declared destination.
    /bin/cp -f "$source_path" "$YOGA_DESTINATION_DIRECTORY/$asset"
done

echo "copied ${#YOGA_ASSETS[@]} Yoga assets to $YOGA_DESTINATION_DIRECTORY"
