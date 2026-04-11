---
name: recall
description: Semantic search MemPalace for past memories. Use when user asks "how did we handle X?" or "/curator:recall <query>".
allowed-tools: Bash
---

# /curator:recall

Live semantic query against MemPalace. Returns top matches with drawer content and source attribution.

**Usage:** `/curator:recall <query>`

## Implementation

```bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

QUERY="$*"
if [ -z "$QUERY" ]; then
  echo "Usage: /curator:recall <query>" >&2
  exit 1
fi

# Primary: live MemPalace query
if mcp_ping 2>/dev/null; then
  response=$(mcp_search "$QUERY" "$(basename "$CLAUDE_PROJECT_ROOT")" "" 2>/dev/null)
  if [ -n "$response" ]; then
    hits=$(echo "$response" | jq -r '.result // [] | length')
    if [ "$hits" -gt 0 ]; then
      echo "[curator] $hits result(s) from MemPalace:"
      echo "$response" | jq -r '.result[] | "- [\(.hall)/\(.room // "?")] \(.text) (\(.metadata.device_id // "unknown"), \(.ts))"'
      exit 0
    fi
    echo "[curator] no results for: $QUERY"
    exit 0
  fi
fi

# Fallback: local pattern-signal.md grep
echo "[curator] ⚠ MemPalace unreachable — falling back to local pattern-signal.md"
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
if [ -f "$ps" ]; then
  grep -i "$QUERY" "$ps" || echo "[curator] no local matches for: $QUERY"
else
  echo "[curator] no local pattern-signal.md; nothing to search"
fi
```
