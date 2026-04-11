---
name: memory
description: Show curator status (pattern-signal entries, mempalace availability, pending proposals). Use when the user runs "/curator:memory" or asks "what does curator remember?".
allowed-tools: Bash
---

# /curator:memory

Displays curator's current state: the local pattern-signal log, the MemPalace CLI availability, and any pending pattern proposals awaiting review.

**Usage:**
- `/curator:memory` — status overview
- `/curator:memory --review` — list deferred pattern proposals

## Implementation

```bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mempalace-cli.sh"

case "${1:-}" in
  --review)
    pp="$CURATOR_STATE/pending-proposals.jsonl"
    if [ ! -s "$pp" ]; then
      echo "[curator] no pending proposals"
      exit 0
    fi
    count=$(wc -l < "$pp")
    echo "[curator] $count pending proposal(s):"
    cat -n "$pp"
    exit 0
    ;;
esac

# Status overview
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"

if [ -f "$ps" ]; then
  ps_entries=$(grep -c "^- " "$ps" 2>/dev/null || echo 0)
  ps_mtime=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$ps" 2>/dev/null || \
             stat -c "%y" "$ps" | cut -d'.' -f1)
  echo "[pattern-signal]   $ps_entries observations · last write $ps_mtime · 7d rolling"
else
  echo "[pattern-signal]   (empty)"
fi

if mempalace_available; then
  ver=$(mempalace_version 2>/dev/null || echo "unknown")
  cmd=$(mempalace_resolved_command)
  echo "[MemPalace CLI]    available (v$ver, $cmd)"
else
  echo "[MemPalace CLI]    not installed — /curator:recall will fall back to local grep"
  echo "                   install: see https://github.com/milla-jovovich/mempalace"
fi

pp="$CURATOR_STATE/pending-proposals.jsonl"
if [ -s "$pp" ]; then
  pp_count=$(wc -l < "$pp")
  echo "[pending proposals] $pp_count items — run /curator:memory --review"
else
  echo "[pending proposals] 0"
fi
```
