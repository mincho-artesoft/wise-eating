#!/usr/bin/env bash
#
# Park the current image set and start the catalogue again from zero.
#
#   ./fresh-start.sh            show exactly what would happen, change nothing
#   ./fresh-start.sh --go       do it
#
# Why regenerate rather than sort: the images on disk were produced across five
# extension versions, four of which could attach one job's image to another job's
# filename. That failure leaves a correctly-named, single, plausible-looking file
# — invisible to every check in the pipeline. Four were confirmed by eye; the true
# count is unknown and not cheaply knowable. With image credits at zero the honest
# move is to stop trying to tell good from bad and rebuild the set under one
# extension version.
#
# NOTHING IS DELETED. The old set is renamed with a timestamp and left alongside.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HOME/wise-eating-images}"
REPO="${REPO:-$HOME/work/wise-eating}"
GO=0; [[ "${1:-}" == "--go" ]] && GO=1
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="${OUT}-pre-${STAMP}"

c()  { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok() { c '0;32' "  ok    $1"; }
warn(){ c '0;33' "  warn  $1"; }
die() { c '0;31' "  FAIL  $1"; exit 1; }
say() { printf '  %s\n' "$1"; }

echo
c '1' "fresh start — $([[ $GO == 1 ]] && echo 'LIVE' || echo 'dry run, nothing will change')"
echo

# --- 1. refuse if anything is still running -------------------------------
# Renaming the output directory out from under a live runner loses whatever it
# downloads next, and the runner would silently recreate the path.
if pgrep -f "[r]unner\.js" >/dev/null 2>&1 || pgrep -f "[l]oop\.sh" >/dev/null 2>&1; then
  die "a runner or loop is still running. Stop it first:
            pkill -f 'loop\.sh'; pkill -f 'runner\.js'"
fi
ok "no runner or loop running"

# --- 2. what is there now -------------------------------------------------
if [[ -d "$OUT" ]]; then
  N="$(find "$OUT" -maxdepth 1 -type f \( -name '*.jpeg' -o -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) | wc -l | tr -d ' ')"
  SZ="$(du -sh "$OUT" 2>/dev/null | cut -f1)"
  say "current set : $N image(s), $SZ  ->  will be renamed to"
  say "              $ARCHIVE"
else
  N=0
  say "current set : none ($OUT does not exist)"
fi

# --- 3. the ledger --------------------------------------------------------
# Keyed by filename, so a stale entry would be overwritten rather than confuse
# anything — but the counts it reports would mix two different runs together,
# and the media ids in it point at images about to be abandoned.
LED="$DIR/results/ledger.json"
if [[ -f "$LED" ]]; then
  ROWS="$(python3 -c "import json;print(len(json.load(open('$LED'))))" 2>/dev/null || echo '?')"
  say "ledger      : $ROWS row(s)  ->  results/ledger-pre-${STAMP}.json"
fi

# --- 4. what stays --------------------------------------------------------
say "jobs.json   : UNCHANGED — 1,844 prompts, styleHash must not move."
say "              Rebuilding it risks a different styleHash, and verify.py's"
say "              check C exists to catch exactly that. Leave it alone."
echo

if [[ $GO != 1 ]]; then
  c '1' "dry run — nothing changed. Re-run with --go to proceed."
  echo
  exit 0
fi

# --- 5. do it -------------------------------------------------------------
if [[ -d "$OUT" ]] && (( N > 0 )); then
  mv "$OUT" "$ARCHIVE" || die "could not rename $OUT"
  ok "parked $N image(s) -> $ARCHIVE"
fi
mkdir -p "$OUT" || die "could not create $OUT"
ok "fresh output directory: $OUT"

if [[ -f "$LED" ]]; then
  mv "$LED" "$DIR/results/ledger-pre-${STAMP}.json" && ok "parked the ledger"
fi
rm -f "$DIR/results/_current-slice.json" 2>/dev/null || true

echo
c '1' "verifying the job list against an empty output directory"
python3 "$DIR/verify.py" --repo "$REPO" --out "$OUT" | sed 's/^/     /' || die "verify failed"

echo
c '1' "ready"
say "start the full run with:"
say ""
say "    cd $DIR && nohup ./loop.sh > loop.log 2>&1 &"
say ""
say "watch it with:  tail -f $DIR/loop.log"
say "check progress: python3 $DIR/status.py --out $OUT"
say ""
say "the parked set is still at $ARCHIVE — delete it only once the new run has"
say "finished and you have spot-checked it."
echo
