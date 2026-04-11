#!/usr/bin/env bash
# memory-bridge/project.sh — SessionStart projection: MemPalace → MEMORY.md.
# Required env: CLAUDE_PROJECT_ROOT, CURATOR_HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$CURATOR_HOME/core/lib/common.sh"
source "$CURATOR_HOME/core/lib/mcp-client.sh"

: "${CLAUDE_PROJECT_ROOT:?CLAUDE_PROJECT_ROOT must be set}"

mem_dir="$CLAUDE_PROJECT_ROOT/memory"
mem_file="$mem_dir/MEMORY.md"
template="$CURATOR_HOME/core/templates/MEMORY.md.template"

mkdir -p "$mem_dir"

# 1. Back up existing MEMORY.md (idempotent; skip if already backed up this second)
if [ -f "$mem_file" ] && [ -s "$mem_file" ]; then
  ts=$(date -u +%Y%m%d-%H%M%S)
  backup="$mem_dir/backup-$ts"
  mkdir -p "$backup"
  cp "$mem_file" "$backup/MEMORY.md"
fi

# 2. Try to pull L0 rules from MemPalace
project_name="$(basename "$CLAUDE_PROJECT_ROOT")"
wing_name="$project_name"
source_tier="fresh"
l0_rules=""

if mcp_ping 2>/dev/null; then
  resp=$(mcp_search "L0 absolute rules" "$wing_name" "hall_facts" 2>/dev/null || echo "")
  if [ -n "$resp" ]; then
    l0_rules=$(echo "$resp" | jq -r '.result // [] | map("- " + .text) | join("\n")')
  fi
else
  source_tier="stale"
fi

# 3. Render template
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ ! -f "$template" ]; then
  curator_log ERROR "template missing: $template"
  exit 1
fi

sed \
  -e "s|__PROJECTION_TS__|$now|g" \
  -e "s|__PROJECT_NAME__|$project_name|g" \
  -e "s|__WING_NAME__|$wing_name|g" \
  "$template" > "$mem_file"

# Override source tier in banner if stale
if [ "$source_tier" = "stale" ]; then
  sed -i.bak "s|source=fresh|source=stale|" "$mem_file" && rm "$mem_file.bak"
fi

# Append pulled L0 rules if any
if [ -n "$l0_rules" ]; then
  printf "\n%s\n" "$l0_rules" >> "$mem_file"
fi

curator_log INFO "projection written: $mem_file (source=$source_tier)"
