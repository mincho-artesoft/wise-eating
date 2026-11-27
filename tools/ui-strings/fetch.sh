#!/bin/bash
# Copy the strings the Swift compiler extracted in the last build on the second
# Mac (tools/search-golden/remote.sh test builds there) into work/stringsdata.
# Only a real build knows which literals are localisable and what their format
# specifiers are; `xcstringstool extract` without type checking does not.
set -euo pipefail
HOST="${AYURVEDA_REMOTE:-photovault-render}"
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/work/stringsdata"
rm -rf "$out"
mkdir -p "$out"
ssh -o BatchMode=yes "$HOST" \
    'cd "Ayurveda-ios/dd/Build/Intermediates.noindex/Ayurveda & Asana Yoga.build/Debug-iphonesimulator" &&
     tar cf - "Ayurveda & Asana Yoga.build/Objects-normal/arm64/"*.stringsdata \
              AyuraLiveActivityWidget.build/Objects-normal/arm64/*.stringsdata' | tar xf - -C "$out"
echo "$(find "$out" -name '*.stringsdata' | wc -l | tr -d ' ') stringsdata files in $out"
