#!/usr/bin/env bash
# core/hooks/session-start.sh — CC SessionStart hook entry point.
# Non-blocking (15s timeout in settings.json). Fire-and-forget behavior: any
# internal failure just logs and returns 0 to avoid blocking session start.

set -uo pipefail  # NOTE: no -e — we never want to fail the whole session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
set +e  # restore: common.sh sets -euo pipefail; hook must never block session

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_PROJECT_ROOT:=$PWD}"
: "${CLAUDE_SESSION_ID:=$(date +%s)-$$}"

mkdir -p "$CURATOR_STATE"

# 1. Reset per-session state
jq -cn \
  --arg sid "$CLAUDE_SESSION_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{session_id:$sid, started_at:$ts, proposal_count:0, last_proposal_ts:null}' \
  > "$CURATOR_STATE/session-state.json"

# 2. Run projection (never blocks session)
if ! "$CURATOR_HOME/memory-bridge/project.sh"; then
  curator_log WARN "project.sh failed — continuing with stale MEMORY.md"
fi

# 3. Run reconcile (best effort)
if ! "$CURATOR_HOME/memory-bridge/reconcile.sh"; then
  curator_log WARN "reconcile.sh failed — will retry next session"
fi

# 4. Compute staleness tier and emit banner to stderr (CC routes stderr to user)
mem_file="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
if [ -f "$mem_file" ]; then
  banner=$(head -n 1 "$mem_file")
  if [[ "$banner" == *source=stale* ]]; then
    proj_ts=$(echo "$banner" | sed -n 's/.*projection-ts=\([^ ]*\).*/\1/p')
    now=$(date -u +%s)
    proj_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$proj_ts" +%s 2>/dev/null || \
                 date -u -d "$proj_ts" +%s 2>/dev/null || echo "$now")
    age=$((now - proj_epoch))
    if [ "$age" -ge 86400 ]; then
      echo "[curator] ⚠ using cached memory (stale >24h), MemPalace unreachable" >&2
    elif [ "$age" -ge 300 ]; then
      echo "[curator] ⚠ using cached memory (stale ${age}s), MemPalace unreachable" >&2
    fi
    # <5min is silent
  fi
fi

exit 0
