---
name: recall
description: Search MemPalace for past memories via the mempalace CLI. Use when user asks "how did we handle X?" or "/curator:recall <query>".
allowed-tools: Bash
---

# /curator:recall

Shells out to the `mempalace search` CLI for semantic recall against the user's MemPalace install. If MemPalace is not available, falls back to a `grep` over the local `pattern-signal.md` file.

**Usage:** `/curator:recall <query>`

## Implementation

```bash
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mempalace-cli.sh"

QUERY="$*"
if [ -z "$QUERY" ]; then
  echo "Usage: /curator:recall <query>" >&2
  exit 1
fi

# Primary path: real semantic search via mempalace CLI
if mempalace_available; then
  wing="$(basename "$CLAUDE_PROJECT_ROOT" | tr '-' '_')"
  echo "[curator] searching mempalace (wing=$wing)..."
  mempalace_search "$QUERY" "$wing" 5
  exit 0
fi

# Fallback: local pattern-signal grep
echo "[curator] mempalace not installed — searching local pattern-signal.md instead"
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
if [ -f "$ps" ]; then
  if ! grep -i "$QUERY" "$ps"; then
    echo "[curator] no local matches for: $QUERY"
  fi
else
  echo "[curator] no local pattern-signal.md; nothing to search"
fi
```
