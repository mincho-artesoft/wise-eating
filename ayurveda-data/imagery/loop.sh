#!/usr/bin/env bash
#
# Unattended, gentle, resumable. Runs small batches with long pauses until every
# image exists, and stops itself the moment Flow objects.
#
#   ./loop.sh                    continuous, no pauses, until every image exists
#   MAX_PER_DAY=100 ./loop.sh    add a daily ceiling if it gets blocked again
#   BATCH=10 PAUSE=900 ./loop.sh gentle
#   nohup ./loop.sh > loop.log 2>&1 &      leave it running for days
#
# Continuous by default: no pause between batches, effectively unlimited rounds,
# and a backoff only cools briefly rather than stopping.
#
# ONE thing still stops it: Flow actually refusing. Continuing to submit into a
# service that has said no is what turns a temporary block into a permanent one,
# and that is the single behaviour this file will not do. Everything else it
# rides out.
#
# It will NOT create Flow projects, rotate between them, or otherwise react to
# throttling by finding more capacity. If the service pushes back, this stops.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH="${BATCH:-25}"
PAUSE="${PAUSE:-0}"             # no pause between batches by default
SETTLE="${SETTLE:-15000}"
# 0 = no daily ceiling (the default: go as fast as the service allows).
#
# Worth knowing what it is for. The run that got flagged did ~100 images in 3.3
# hours and tripped at roughly 130 for the day, which looks more like a volume
# limit than a rate limit. If a fast run trips again, MAX_PER_DAY=100 is the knob
# that tests that reading. Running without it is not reckless — the refusal
# detector stops the loop within seconds rather than hammering — it just means
# finding the limit by hitting it.
MAX_PER_DAY="${MAX_PER_DAY:-0}"
MAX_ROUNDS="${MAX_ROUNDS:-100000}"
OUT="${OUT:-$HOME/wise-eating-images}"
REPO="${REPO:-$HOME/work/wise-eating}"
STATE="$DIR/loop-state.txt"

log() { printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$STATE"; }

remaining() {
  python3 "$DIR/status.py" --out "$OUT" --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["missing"])' 2>/dev/null || echo "?"
}

DAY=""; DAY_COUNT=0; MISSES=0; BACKOFFS=0
MAX_BACKOFFS="${MAX_BACKOFFS:-1000}"
MAX_MISSES="${MAX_MISSES:-30}"
done_count() {
  python3 "$DIR/status.py" --out "$OUT" --json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["done"])' 2>/dev/null || echo 0
}

log "loop starting — batch $BATCH, pause ${PAUSE}s, settle ${SETTLE}ms, cap $( ((MAX_PER_DAY>0)) && echo "${MAX_PER_DAY}/day" || echo "none")"
log "remaining: $(remaining)"

for round in $(seq 1 "$MAX_ROUNDS"); do
  TODAY="$(date -u +%Y-%m-%d)"
  if [[ "$TODAY" != "$DAY" ]]; then DAY="$TODAY"; DAY_COUNT=0; log "new day $DAY — daily counter reset"; fi
  if (( MAX_PER_DAY > 0 && DAY_COUNT >= MAX_PER_DAY )); then
    # Deliberately not computing "seconds until midnight": that needs GNU date on
    # Linux and BSD date on macOS, and a failure in either branch would take the
    # whole loop down. Sleeping a fixed hour and re-checking the date costs
    # nothing and works everywhere.
    log "daily cap reached ($DAY_COUNT/$MAX_PER_DAY) — sleeping 1h, will resume when the date rolls over"
    sleep 3600
    continue
  fi

  REM="$(remaining)"
  if [[ "$REM" == "0" ]]; then
    log "round $round — nothing left to generate. Done."
    break
  fi
  log "round $round — $REM remaining, starting a batch of $BATCH"

  # < /dev/null so nothing downstream can ever wait on a terminal that is not there
  OUTPUT="$(LIMIT="$BATCH" SETTLE="$SETTLE" OUT="$OUT" REPO="$REPO" "$DIR/run.sh" 2>&1 < /dev/null)"
  RC=$?
  printf '%s\n' "$OUTPUT" | tee -a "$STATE" >/dev/null
  printf '%s\n' "$OUTPUT" | tail -25

  # A REFUSAL ends the loop. A backoff does not.
  #
  # These were conflated in one pattern and it cost a night: six card-bind stalls
  # tripped the runner's backoff, the loop read "BACKING OFF" as a refusal, and
  # stopped — while reconciliation was recovering five of the six images. Flow had
  # said nothing. Only Flow actually objecting is a reason to stop.
  if printf '%s' "$OUTPUT" | grep -qiE "FLOW_REFUSED|unusual activity"; then
    log "STOPPED — Flow refused the request. This is an anti-abuse or quota block."
    log "  Do not restart this loop today. Wait several hours, then generate ONE"
    log "  image by hand in the Flow UI. Only if that works, start again with a"
    log "  smaller BATCH and a longer PAUSE."
    exit 2
  fi
  if printf '%s' "$OUTPUT" | grep -q "BACKING OFF"; then
    BACKOFFS=$(( BACKOFFS + 1 ))
    COOL=$(( PAUSE > 0 ? PAUSE * 4 : 60 ))
    log "runner backed off (${BACKOFFS}/${MAX_BACKOFFS}) — cooling ${COOL}s, then continuing"
    if (( BACKOFFS >= MAX_BACKOFFS )); then
      log "STOPPED — the runner has backed off ${MAX_BACKOFFS} times in a row."
      log "  Flow has not refused anything; this is sustained unrecoverable failure."
      log "  Worth looking at the tab before continuing."
      exit 5
    fi
    sleep "$COOL"; continue
  fi
  BACKOFFS=0
  if [[ $RC -ne 0 ]]; then
    # "extension never connected" is transient — Chrome may be closed, the tab may
    # have been navigated away, the laptop may have slept. Over a multi-day run
    # that should not end the loop on the first occurrence.
    if printf '%s' "$OUTPUT" | grep -q "extension never connected"; then
      MISSES=$(( MISSES + 1 ))
      log "extension not connected (${MISSES}/${MAX_MISSES}) — waiting ${PAUSE}s and trying again"
      if (( MISSES >= MAX_MISSES )); then
        log "STOPPED — the extension has not connected ${MAX_MISSES} times in a row."
        log "  Open Chrome with an authenticated Flow project tab, reload the tab to wake"
        log "  the extension's service worker, then start the loop again."
        exit 4
      fi
      sleep $(( PAUSE > 0 ? PAUSE : 60 )); continue
    fi
    log "run.sh exited $RC — stopping so it can be looked at rather than looped over"
    exit "$RC"
  fi
  MISSES=0

  NOW="$(remaining)"
  DAY_COUNT=$(( DAY_COUNT + REM - NOW ))
  log "round $round done — $NOW remaining, $DAY_COUNT generated today"
  if [[ "$NOW" == "$REM" ]]; then
    # A full batch that produced nothing is a problem no amount of waiting fixes.
    log "STOPPED — a whole batch completed without producing a single new image."
    exit 3
  fi
  [[ "$NOW" == "0" ]] && { log "all images generated"; break; }

  if (( PAUSE > 0 )); then log "pausing ${PAUSE}s"; fi
  sleep "$PAUSE"
done

log "loop finished — $(remaining) remaining"
python3 "$DIR/status.py" --out "$OUT" | tee -a "$STATE"
