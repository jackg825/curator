#!/usr/bin/env bash
# core/hooks/stop.sh — CC Stop hook entry point.
# 10min timeout. Maintains the pattern-signal.md 7-day rolling window.
#
# v1.2 scope: pattern-signal pruning ONLY. The pending_sync flush via
# reconcile.sh was deleted because curator no longer writes to MemPalace
# (mempalace's own plugin handles auto-save; see issue #1).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
set +e  # restore: hook must never block session

: "${CLAUDE_PROJECT_ROOT:=$PWD}"

# Prune pattern-signal.md to last 7 days
ps="$CLAUDE_PROJECT_ROOT/memory/pattern-signal.md"
if [ -f "$ps" ]; then
  cutoff=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
           date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)

  tmp=$(mktemp)
  # Keep banner (first line) + entries newer than cutoff
  head -n 1 "$ps" > "$tmp"
  awk -v cutoff="$cutoff" '
    /^- / {
      ts = $2
      if (ts >= cutoff) print
      next
    }
    # Keep blank lines and non-entry lines (section headers, etc.)
    !/^- / && NR > 1 { print }
  ' "$ps" >> "$tmp"
  mv "$tmp" "$ps"
  # Touch mtime so Sonnet selector sees it as recently updated
  touch "$ps"
fi

exit 0
