---
name: capture
description: Write a memory to MemPalace immediately with idempotent journaling. Use when the user says "remember this" or "/curator:capture <text>".
allowed-tools: Bash
---

# /curator:capture

Writes a memory to MemPalace right now. Goes through the pending_sync journal so failures retry automatically on next SessionStart.

**Usage:**
- `/curator:capture <text>` — capture as a feedback-type memory
- `/curator:capture --pin <text>` — also append to MEMORY.md L0 section (reserves as absolute rule)

## Implementation

When the user invokes this skill, execute:

```bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/journal.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

# Parse arguments
PIN=0
DEFER=0
TEXT=""
for arg in "$@"; do
  case "$arg" in
    --pin) PIN=1 ;;
    --defer) DEFER=1 ;;
    *) TEXT="$TEXT $arg" ;;
  esac
done
TEXT="${TEXT# }"

if [ -z "$TEXT" ]; then
  echo "Usage: /curator:capture [--pin] [--defer] <text>" >&2
  exit 1
fi

# Defer path: write to pending-proposals.jsonl for later batch review via /curator:memory --review
if [ "$DEFER" = "1" ]; then
  pp="$CURATOR_STATE/pending-proposals.jsonl"
  mkdir -p "$(dirname "$pp")"
  jq -cn --arg text "$TEXT" \
         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --arg sid "${CLAUDE_SESSION_ID:-unknown}" \
    '{proposal_id: ($ts + "-" + ($text | @base64)[0:8]), ts: $ts, candidate_text: $text, session_id: $sid}' \
    >> "$pp"
  echo "[curator] deferred: $TEXT (review later with /curator:memory --review)"
  exit 0
fi

# Normal path: append to journal with mempalace pending
payload=$(jq -cn --arg text "$TEXT" '{text:$text}')
journal_append "feedback" "$payload"

# Also append to pattern-signal.md for local recency signal
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
mkdir -p "$(dirname "$ps")"
[ -f "$ps" ] || echo "<!-- curator-pattern-signal schema_version=1 -->" > "$ps"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
device=$(curator_device_id)
echo "- $ts | $TEXT | device=$device" >> "$ps"
touch "$ps"

# If --pin: append to MEMORY.md L0 section
if [ "$PIN" = "1" ]; then
  mem_file="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  echo "- $TEXT" >> "$mem_file"
fi

# Try immediate MemPalace write (best effort; journal already has it)
if mcp_write "feedback" "$payload" 2>/dev/null; then
  hash=$(printf "%s\0%s\0%s" "feedback" "$payload" "$ts" | shasum -a 256 | awk '{print $1}')
  journal_mark_resolved "$hash" "mempalace"
  echo "[curator] captured: $TEXT"
else
  echo "[curator] captured locally; will sync on next session (MemPalace unreachable)"
fi
```

After execution, confirm to the user what was captured and where it landed (MemPalace vs pending).
