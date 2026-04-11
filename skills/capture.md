---
name: capture
description: Append a memory to the local 7-day pattern-signal log. Use when the user says "remember this" or "/curator:capture <text>".
allowed-tools: Bash
---

# /curator:capture

Writes a short observation to `pattern-signal.md` — curator's local 7-day rolling log. The Stop hook prunes entries older than 7 days.

For **persistent** cross-session memory, install [MemPalace](https://github.com/milla-jovovich/mempalace) and let its own auto-save Stop hook handle long-term storage. Curator's `/curator:capture` is a lightweight observation log, not a write-through cache (see [issue #1](https://github.com/jackg825/curator/issues/1) for the v1.0 → v1.2 design pivot).

**Usage:** `/curator:capture <text>`

## Implementation

```bash
source "$CURATOR_HOME/core/lib/common.sh"

TEXT="$*"
if [ -z "$TEXT" ]; then
  echo "Usage: /curator:capture <text>" >&2
  exit 1
fi

# Append to pattern-signal.md (local 7d rolling log)
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
mkdir -p "$(dirname "$ps")"
[ -f "$ps" ] || echo "<!-- curator-pattern-signal schema_version=1 -->" > "$ps"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
device=$(curator_device_id)
echo "- $ts | $TEXT | device=$device" >> "$ps"
touch "$ps"

echo "[curator] noted in pattern-signal: $TEXT"
echo "[curator] (this entry expires in 7 days; for permanent storage install mempalace)"
```
