#!/usr/bin/env bash
# core/hooks/session-start.sh — CC SessionStart hook entry point.
# Non-blocking (15s timeout in settings.json). Fire-and-forget behavior: any
# internal failure just logs and returns 0 to avoid blocking session start.
#
# v1.2 scope: reset per-session state ONLY. The L0 projection from MemPalace
# was deleted because mempalace has no concept of "absolute rules" that could
# be projected reliably (see issue #1).

set -uo pipefail  # NOTE: no -e — we never want to fail the whole session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
set +e  # restore: common.sh sets -euo pipefail; hook must never block session

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_SESSION_ID:=$(date +%s)-$$}"

mkdir -p "$CURATOR_STATE"

# Reset per-session state. Used by user-prompt-submit.sh to enforce HR-2
# (one pattern proposal per session).
jq -cn \
  --arg sid "$CLAUDE_SESSION_ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{session_id:$sid, started_at:$ts, proposal_count:0, last_proposal_ts:null}' \
  > "$CURATOR_STATE/session-state.json"

exit 0
