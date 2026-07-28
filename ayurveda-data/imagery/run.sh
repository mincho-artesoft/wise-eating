#!/usr/bin/env bash
#
# One command: clear any stale bridge, start a fresh one, wait for the extension,
# then run the generator. Everything the last few hours kept going wrong by hand.
#
#   ./run.sh                 next 100 images
#   ./run.sh --limit 1844    everything remaining
#   ./run.sh --status        just the reconciliation report, generate nothing
#   ./run.sh --verify        just the "is it safe to restart" check
#   ./run.sh --force         regenerate even rows already on disk (costs credits)
#
# Extra flags are passed straight through to runner.js.
#
set -uo pipefail

PLUGIN="${PLUGIN:-$HOME/chrome plugin}"
REPO="${REPO:-$HOME/work/wise-eating}"
OUT="${OUT:-$HOME/wise-eating-images}"
PORT="${PORT:-8787}"
LIMIT="${LIMIT:-100}"
SETTLE="${SETTLE:-8000}"
ABORT_AFTER="${ABORT_AFTER:-8}"
MIN_EXT_VERSION="0.4.2"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$DIR/bridge.log"
cd "$DIR"

c()  { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok() { c '0;32' "  ok    $1"; }
warn(){ c '0;33' "  warn  $1"; }
die() { c '0;31' "  FAIL  $1"; exit 1; }

# --status: report and stop. Cheap, and worth doing before every run.
if [[ "${1:-}" == "--status" ]]; then
  exec python3 "$DIR/status.py" --out "$OUT"
fi
if [[ "${1:-}" == "--verify" ]]; then
  exec python3 "$DIR/verify.py" --repo "$REPO" --out "$OUT"
fi

echo
c '1' "1/5  clearing port $PORT"
# A HEALTHY bridge is reused. Only an unhealthy one, or one still holding
# in-flight jobs, gets killed.
#
# Killing unconditionally was wrong and broke the unattended loop: the extension
# reconnects from an MV3 service worker whose timer dies with the worker, so once
# the socket closes Chrome terminates it and nothing wakes it again. Restarting
# the bridge every round therefore severed the connection every 25 images. The
# safety property that mattered — never inherit an in-flight job from an earlier
# run — is preserved by checking for pending jobs rather than by churning the
# process.
REUSE=0
if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
  H="$(curl -sf "http://localhost:$PORT/health")"
  PENDING="$(printf '%s' "$H" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("jobs", 0))
except Exception:
    print(1)' 2>/dev/null || echo 1)"
  CONN="$(printf '%s' "$H" | grep -c '"extensionConnected": *true' || true)"
  if [[ "$PENDING" == "0" && "$CONN" == "1" ]]; then
    REUSE=1
    ok "reusing the healthy bridge already on $PORT (extension connected, no jobs held)"
  fi
fi

if [[ "$REUSE" == 0 ]] && lsof -ti:"$PORT" >/dev/null 2>&1; then
  lsof -ti:"$PORT" | xargs kill 2>/dev/null || true
  sleep 1
  lsof -ti:"$PORT" >/dev/null 2>&1 && lsof -ti:"$PORT" | xargs kill -9 2>/dev/null || true
  ok "killed the previous bridge"
elif [[ "$REUSE" == 0 ]]; then
  ok "nothing was listening"
fi

echo
c '1' "2/5  starting the bridge"
[[ -f "$PLUGIN/bridge/server.js" ]] || die "no bridge at $PLUGIN/bridge/server.js — set PLUGIN=..."
if [[ "$REUSE" == 1 ]]; then
  BRIDGE_PID="$(lsof -ti:"$PORT" | head -1)"
  ok "already running as pid $BRIDGE_PID"
else
  : > "$LOG"
  nohup node "$PLUGIN/bridge/server.js" >>"$LOG" 2>&1 &
  BRIDGE_PID=$!
  disown 2>/dev/null || true
  ok "pid $BRIDGE_PID, logging to $LOG"
fi

for _ in $(seq 1 30); do
  curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1 || die "bridge never came up — see $LOG"
ok "bridge responding on $PORT"

echo
c '1' "3/5  waiting for the Chrome extension"
echo "     if this hangs: reload Flow Automator at chrome://extensions, then reload the Flow project tab"
CONNECTED=0
for _ in $(seq 1 180); do
  if curl -sf "http://localhost:$PORT/health" | grep -q '"extensionConnected": *true'; then
    CONNECTED=1; break
  fi
  sleep 1
done
if [[ "$CONNECTED" != 1 ]]; then
  warn "no extension after 180s. The MV3 service worker only reconnects while it is awake;"
  warn "if it was terminated, reloading the Flow project tab wakes it."
  die "extension never connected — is Chrome running with an authenticated Flow project tab open?"
fi

VERSION="$(grep -o 'version [0-9][0-9.]*' "$LOG" | tail -1 | awk '{print $2}')"
if [[ -z "$VERSION" ]]; then
  warn "could not read the extension version from the log"
elif [[ "$VERSION" == "$MIN_EXT_VERSION" || "$(printf '%s\n%s\n' "$MIN_EXT_VERSION" "$VERSION" | sort -V | head -1)" == "$MIN_EXT_VERSION" ]]; then
  ok "extension $VERSION"
else
  # Worth stopping for. Below 0.4.0 the hidden-tab fix is missing and every job
  # whose result card fails to bind stalls for ~195s instead of finishing.
  warn "extension is $VERSION, expected >= $MIN_EXT_VERSION"
  warn "reload the extension at chrome://extensions — reloading the TAB is not enough"
  # Never block on stdin when there is no terminal. Under `nohup ... &` a read
  # here raises SIGTTIN and the whole job is suspended, which is what happened
  # the first time this was run unattended: the loop looked started and was
  # actually frozen waiting for a keypress nobody could give it.
  if [[ -t 0 ]]; then
    read -r -p "  continue anyway? [y/N] " a; [[ "$a" == y* ]] || exit 1
  else
    die "running unattended with an out-of-date extension — reload it and start again"
  fi
fi

echo
c '1' "4/5  verifying the job list"
# Cheap, and it catches the quiet failure: if the filename rule or the style
# prompt drifts, every downloaded image orphans and gets regenerated silently.
if ! python3 "$DIR/verify.py" --repo "$REPO" --out "$OUT" | sed 's/^/     /'; then
  die "job list verification failed — see above; generating now would waste credits"
fi

echo
c '1' "5/5  generating"
python3 "$DIR/status.py" --out "$OUT" | sed 's/^/     /'
echo

node "$DIR/runner.js" --out "$OUT" --no-settings \
  --limit "$LIMIT" --settle "$SETTLE" --abort-after "$ABORT_AFTER" "$@" < /dev/null
RC=$?

echo
c '1' "done"
python3 "$DIR/status.py" --out "$OUT" | sed 's/^/     /'
echo
echo "     bridge still running as pid $BRIDGE_PID (kill: lsof -ti:$PORT | xargs kill)"
exit $RC
