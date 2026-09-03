#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
NARRATION_SOURCE_DIRECTORY="$REPOSITORY_ROOT/Resources/PracticeNarration"
NARRATION_DESTINATION_DIRECTORY="${1:?destination narration resource directory is required}"

if [[ "$(basename "$NARRATION_DESTINATION_DIRECTORY")" != "narration" ]]; then
    echo "ERROR: narration destination must end in /narration" >&2
    exit 1
fi

MANIFEST_PATH="$NARRATION_SOURCE_DIRECTORY/manifest.json"
AUDIO_SOURCE_DIRECTORY="$NARRATION_SOURCE_DIRECTORY/audio"
INPUT_FILE_LIST_PATH="${SCRIPT_INPUT_FILE_LIST_0:?narration input file list is required}"
if [[ ! -f "$MANIFEST_PATH" || ! -d "$AUDIO_SOURCE_DIRECTORY" ]]; then
    echo "MISSING: bundled practice narration delivery" >&2
    exit 1
fi

AUDIO_FILE_COUNT=0
while IFS= read -r declared_path || [[ -n "$declared_path" ]]; do
    relative_path="${declared_path#*Resources/PracticeNarration/}"
    if [[ "$relative_path" == "$declared_path" ]]; then
        echo "ERROR: unexpected narration input path: $declared_path" >&2
        exit 1
    fi
    source_path="$NARRATION_SOURCE_DIRECTORY/$relative_path"
    destination_path="$NARRATION_DESTINATION_DIRECTORY/$relative_path"
    if [[ ! -f "$source_path" ]]; then
        echo "MISSING: $source_path" >&2
        exit 1
    fi
    /bin/mkdir -p "$(dirname "$destination_path")"
    /bin/cp -f "$source_path" "$destination_path"
    if [[ "$relative_path" == *.mp3 ]]; then
        AUDIO_FILE_COUNT=$((AUDIO_FILE_COUNT + 1))
    fi
done < "$INPUT_FILE_LIST_PATH"

if [[ "$AUDIO_FILE_COUNT" != "601" ]]; then
    echo "ERROR: expected 601 MP3 inputs; found $AUDIO_FILE_COUNT" >&2
    exit 1
fi

echo "copied $AUDIO_FILE_COUNT recorded practice cues to $NARRATION_DESTINATION_DIRECTORY"
