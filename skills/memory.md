---
name: memory
description: Show curator status (MEMORY.md, pattern-signal, MemPalace connection, pending proposals). Use when user runs "/curator:memory" or asks "what does curator remember?".
allowed-tools: Bash
---

# /curator:memory

Displays curator's current state: the L0 MEMORY.md summary, pattern-signal status, MemPalace connection tier, and any pending pattern proposals awaiting review.

**Usage:**
- `/curator:memory` — status overview
- `/curator:memory --review` — batch-review deferred pattern proposals
- `/curator:memory --edit` — open MEMORY.md in $EDITOR

## Implementation

```bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

case "${1:-}" in
  --edit)
    "${EDITOR:-vi}" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
    exit 0
    ;;
  --review)
    pp="$CURATOR_STATE/pending-proposals.jsonl"
    if [ ! -s "$pp" ]; then
      echo "[curator] no pending proposals"
      exit 0
    fi
    count=$(wc -l < "$pp")
    echo "[curator] $count pending proposal(s):"
    cat -n "$pp" | jq -r '[.[0], (.[1:] | join(" "))] | @tsv' 2>/dev/null || cat -n "$pp"
    echo
    echo "To confirm: /curator:capture <text>"
    echo "To clear all: rm $pp"
    exit 0
    ;;
esac

# Default: status overview (HR-3 format)
mem="$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"

if [ -f "$mem" ]; then
  l0_entries=$(grep -c "^- " "$mem" 2>/dev/null || echo 0)
  l0_bytes=$(wc -c < "$mem")
  l0_human=$(awk -v b="$l0_bytes" 'BEGIN{printf "%.1fKB", b/1024}')
  echo "[MEMORY.md]     L0 · $l0_entries entries · $l0_human · schema v1"
else
  echo "[MEMORY.md]     (not yet initialized)"
fi

if [ -f "$ps" ]; then
  ps_entries=$(grep -c "^- " "$ps" 2>/dev/null || echo 0)
  ps_mtime=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$ps" 2>/dev/null || \
             stat -c "%y" "$ps" | cut -d'.' -f1)
  echo "[pattern-signal] $ps_entries observations · last write $ps_mtime"
else
  echo "[pattern-signal] (empty)"
fi

if mcp_ping 2>/dev/null; then
  pending_count=0
  if [ -f "$CURATOR_STATE/pending_sync.jsonl" ]; then
    pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' \
      "$CURATOR_STATE/pending_sync.jsonl" 2>/dev/null || echo 0)
  fi
  echo "[MemPalace]     connected · $pending_count pending write(s)"
else
  banner=$(head -n 1 "$mem" 2>/dev/null || echo "")
  proj_ts=$(echo "$banner" | sed -n 's/.*projection-ts=\([^ ]*\).*/\1/p')
  echo "[MemPalace]     disconnected · last sync $proj_ts"
fi

pp="$CURATOR_STATE/pending-proposals.jsonl"
if [ -s "$pp" ]; then
  pp_count=$(wc -l < "$pp")
  echo "[pending proposals] $pp_count items — run /curator:memory --review"
else
  echo "[pending proposals] 0"
fi
```
