#!/bin/bash
# Run the golden search queries (Tests/FoodSearch) on the second Mac, where the
# build does not compete with everything else running on this one.
#
#   tools/search-golden/remote.sh push     mirror what the build needs
#   tools/search-golden/remote.sh sim      create/boot this project's own simulator
#   tools/search-golden/remote.sh test     push + build + run the golden test
#   tools/search-golden/remote.sh pull     copy out/actual.json and out/timing.json back
#   tools/search-golden/remote.sh run      test + pull + compare with the baseline
#   tools/search-golden/remote.sh clean    remove the remote build products
#
# NAME_FIRST=0 in front of test/run turns the name-first search flag off.
#
# The simulator is this project's own (AyurvedaSearchQA), so the simulators
# other work has booted on that Mac are left alone.
set -euo pipefail

HOST="${AYURVEDA_REMOTE:-photovault-render}"
DIR="Ayurveda-ios"
DEVICE="AyurvedaSearchQA"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

remote() { ssh -o BatchMode=yes "$HOST" "$@"; }
udid() { remote "xcrun simctl list devices | sed -n 's/^ *$DEVICE (\([0-9A-F-]*\)).*/\1/p' | head -1"; }

case "${1:-}" in
push)
    remote "mkdir -p $DIR/src $DIR/golden"
    cd "$repo"
    rsync -a --delete -R \
        --exclude '.DS_Store' --exclude 'xcuserdata' --exclude '*.xcuserstate' \
        "Ayurveda & Asana Yoga.xcodeproj" Ayura AyuraLiveActivityWidget Tests tools Resources \
        GenerateUSDAWeeklyMealPlanIntent.swift \
        ayurveda-data/yoga/asanas.json ayurveda-data/yoga/sequences.json ayurveda-data/yoga/sequences.json.gz \
        "$HOST:$DIR/src/"
    rsync -a "$here/golden_queries.json" "$HOST:$DIR/golden/"
    ;;
sim)
    id="$(udid)"
    if [ -z "$id" ]; then
        runtime="$(remote "xcrun simctl list runtimes | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)\$/\1/p' | tail -1")"
        id="$(remote "xcrun simctl create $DEVICE $DEVICE_TYPE $runtime")"
    fi
    remote "xcrun simctl bootstatus $id -b >/dev/null"
    echo "$id"
    ;;
test)
    "$0" push
    id="$("$0" sim | tail -1)"
    remote "df -h ~ | tail -1"
    remote "rm -rf $DIR/golden/out && cd $DIR/src && \
        TEST_RUNNER_SEARCH_GOLDEN_DIR=\$HOME/$DIR/golden \
        TEST_RUNNER_SWIFT_DETERMINISTIC_HASHING=1 \
        TEST_RUNNER_SEARCH_NAME_FIRST=${NAME_FIRST:-1} \
        xcodebuild test -project 'Ayurveda & Asana Yoga.xcodeproj' -scheme YearlyReviewQA \
        -destination id=$id -derivedDataPath \$HOME/$DIR/dd \
        -only-testing:YearlyReviewTests/FoodSearchGoldenTests \
        -only-testing:YearlyReviewTests/AssistantToolsTests \
        > \$HOME/$DIR/test.log 2>&1; rc=\$?; \
        grep -E 'ASSISTANT_RECIPE\||SEARCH_GOLDEN\||SEARCH_BINARY\||SEARCH_YOGA\||SEARCH_NAMES\||error:|XCTAssert|Test Case|\*\* TEST' \$HOME/$DIR/test.log | tail -60; exit \$rc"
    ;;
pull)
    mkdir -p "$here/out"
    rsync -a "$HOST:$DIR/golden/out/" "$here/out/"
    ;;
run)
    "$0" test
    "$0" pull
    python3 "$here/compare.py"
    ;;
clean)
    remote "rm -rf $DIR/dd"
    ;;
*)
    sed -n '2,14p' "$0"
    exit 1
    ;;
esac
