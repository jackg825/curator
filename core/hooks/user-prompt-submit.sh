#!/usr/bin/env bash
# core/hooks/user-prompt-submit.sh — CC UserPromptSubmit hook.
# Emits ONE pattern proposal per session (HR-2). Exit 2 = show stderr to model.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
set +e

: "${CURATOR_STATE:=$HOME/.curator}"
: "${CLAUDE_SESSION_ID:=$(date +%s)-$$}"

state_file="$CURATOR_STATE/session-state.json"
candidates_dir="$CURATOR_STATE/pattern-candidates"
candidate_file="$candidates_dir/${CLAUDE_SESSION_ID}.txt"

[ -d "$candidates_dir" ] || mkdir -p "$candidates_dir"

# If session state missing, initialize (we may be fired before session-start)
[ -f "$state_file" ] || \
  jq -cn --arg sid "$CLAUDE_SESSION_ID" \
    '{session_id:$sid, proposal_count:0, last_proposal_ts:null}' \
    > "$state_file"

# HR-2: cap at one proposal per session
proposal_count=$(jq -r '.proposal_count // 0' "$state_file")
if [ "$proposal_count" -ge 1 ]; then
  exit 0
fi

# No candidate? Silent pass-through.
if [ ! -s "$candidate_file" ]; then
  exit 0
fi

candidate_text=$(cat "$candidate_file")

# Increment proposal_count atomically
tmp=$(mktemp)
jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.proposal_count = ((.proposal_count // 0) + 1) | .last_proposal_ts = $ts' \
   "$state_file" > "$tmp"
mv "$tmp" "$state_file"

# Consume the candidate (one-shot)
: > "$candidate_file"

# Emit proposal via exit 2 (stderr → model)
cat >&2 <<EOF
[curator] pattern detected:

  "$candidate_text"

Reply Y/n/d — Y to capture, n to skip, d to defer to /curator:memory --review
EOF
exit 2
