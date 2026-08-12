#!/usr/bin/env bash
# Clear a stale in-flight job and bring the bridge back up.
#
# When a run is cancelled or blocked mid-job, the bridge keeps that job marked
# in flight. runner.js then refuses to start, and it is right to: that job can
# still finish, download under its own filename, and interleave with the next
# run. That is how an image ends up attached to the wrong row. The state lives
# only in the bridge's memory, so restarting the process is the whole fix.
#
# After this, RELOAD THE FLOW TAB. The extension only reattaches to the new
# bridge process when the page reloads; without it extensionConnected stays
# false and the runner sits on "waiting for the bridge".
set -u
PLUGIN="${PLUGIN:-$HOME/chrome plugin}"

echo "==> killing anything on :8787"
lsof -ti:8787 | xargs kill 2>/dev/null || echo "    (nothing was listening)"
sleep 1

echo "==> starting the bridge"
nohup node "$PLUGIN/bridge/server.js" > "$HOME/bridge.log" 2>&1 &
sleep 3

echo "==> health"
if ! curl -s --max-time 5 localhost:8787/health; then
  echo
  echo "!! the bridge did not come up. Last lines of ~/bridge.log:"
  tail -20 "$HOME/bridge.log"
  exit 1
fi
echo
echo
echo "Now reload the Flow project tab (Cmd-R), then check:"
echo "    curl -s localhost:8787/health          # want \"extensionConnected\": true"
echo "    grep -i version ~/bridge.log | tail -3 # want 0.6.1"
