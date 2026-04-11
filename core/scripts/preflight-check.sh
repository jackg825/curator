#!/usr/bin/env bash
# core/scripts/preflight-check.sh — scan existing ~/.claude for curator install collisions.
# Usage: preflight-check.sh
# Exit code: 0 if safe to install (with warnings possibly), 1 if hard blockers exist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"

REPORT="$CURATOR_STATE/preflight-$(date -u +%Y%m%d-%H%M%S).log"
mkdir -p "$CURATOR_STATE"
: > "$REPORT"

say() {
  echo "$@"
  echo "$@" >> "$REPORT"
}

blockers=0
warnings=0

say "# Curator preflight check — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say ""

# --- 1. Required binaries ---
say "## Binaries"
for bin in jq yq shasum; do
  if command -v "$bin" >/dev/null 2>&1; then
    say "  [OK] $bin"
  else
    say "  [BLOCKER] missing: $bin (brew install $bin)"
    blockers=$((blockers + 1))
  fi
done
say ""

# --- 2. Skill name collisions ---
say "## Skill name collisions"
for name in capture recall memory build; do
  collision=""
  [ -d "$CLAUDE_HOME/skills/$name" ] && collision="$CLAUDE_HOME/skills/$name"
  [ -d "$CLAUDE_HOME/skills/curator-$name" ] && collision="$collision $CLAUDE_HOME/skills/curator-$name"
  if [ -n "$collision" ]; then
    say "  [BLOCKER] collision for '$name': $collision"
    blockers=$((blockers + 1))
  else
    say "  [OK] $name — no collision"
  fi
done
say ""

# --- 3. Hook slot audit ---
say "## Hook slot audit"
settings="$CLAUDE_HOME/settings.json"
if [ -f "$settings" ]; then
  for slot in SessionStart UserPromptSubmit Stop; do
    count=$(jq -r --arg s "$slot" '.hooks[$s] // [] | length' "$settings" 2>/dev/null || echo 0)
    if [ "$count" = "0" ]; then
      say "  [OK] $slot — empty (clean append)"
    else
      say "  [INFO] $slot — $count existing hooks (curator will append at end; order matters for Stop)"
      warnings=$((warnings + 1))
    fi
  done
else
  say "  [INFO] no settings.json yet — will be created on install"
fi
say ""

# --- 4. Existing memdir content ---
say "## Existing memdir content"
projects_dir="$CLAUDE_HOME/projects"
if [ -d "$projects_dir" ]; then
  found=0
  while IFS= read -r mem; do
    repo=$(basename "$(dirname "$(dirname "$mem")")")
    say "  [BACKUP] $repo has populated MEMORY.md (will be backed up by install.sh)"
    warnings=$((warnings + 1))
    found=$((found + 1))
  done < <(find "$projects_dir" -maxdepth 4 -name "MEMORY.md" -size +0 2>/dev/null)
  [ "$found" -eq 0 ] && say "  [OK] no populated MEMORY.md files"
else
  say "  [OK] no projects directory yet"
fi
say ""

# --- 5. MemPalace CLI (optional dependency in v1.2) ---
say "## MemPalace CLI"
source "$SCRIPT_DIR/../lib/mempalace-cli.sh"
if mempalace_available; then
  say "  [OK] mempalace CLI available — /curator:recall will use semantic search"
else
  say "  [INFO] mempalace CLI not found — /curator:recall will fall back to local pattern-signal grep"
  say "         install hint: see https://github.com/milla-jovovich/mempalace"
  warnings=$((warnings + 1))
fi
say ""

# --- Summary ---
say "## Summary"
say "  blockers: $blockers"
say "  warnings: $warnings"
say ""
say "Report saved to: $REPORT"

if [ "$blockers" -gt 0 ]; then
  say ""
  say "PREFLIGHT FAILED — resolve blockers before running install.sh"
  exit 1
fi

say ""
say "PREFLIGHT OK — safe to install"
exit 0
