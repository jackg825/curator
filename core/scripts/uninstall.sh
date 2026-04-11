#!/usr/bin/env bash
# core/scripts/uninstall.sh — reverse install.sh via install-receipt.json.
# Flags: --keep-state (default: preserve ~/.curator), --purge (delete ~/.curator)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"
: "${CURATOR_HOME:=$(cd "$SCRIPT_DIR/../.." && pwd)}"

MODE="keep"  # keep | purge
for arg in "$@"; do
  case "$arg" in
    --keep-state) MODE="keep" ;;
    --purge) MODE="purge" ;;
  esac
done

receipt="$CURATOR_STATE/install-receipt.json"
if [ ! -f "$receipt" ]; then
  curator_log WARN "no install receipt at $receipt — will still attempt best-effort cleanup"
fi

# --- 1. Remove hook entries matching curator commands from settings.json ---
settings="$CLAUDE_HOME/settings.json"
if [ -f "$settings" ]; then
  tmp=$(mktemp)
  jq --arg curator_home "$CURATOR_HOME" '
    .hooks //= {} |
    (.hooks.SessionStart // []) as $ss |
    (.hooks.UserPromptSubmit // []) as $us |
    (.hooks.Stop // []) as $st |
    .hooks.SessionStart = ($ss | map(select(.hooks[0].command | startswith($curator_home) | not))) |
    .hooks.UserPromptSubmit = ($us | map(select(.hooks[0].command | startswith($curator_home) | not))) |
    .hooks.Stop = ($st | map(select(.hooks[0].command | startswith($curator_home) | not)))
  ' "$settings" > "$tmp"
  mv "$tmp" "$settings"
  curator_log INFO "removed curator hooks from $settings"
fi

# --- 2. Remove skill symlinks ---
# NOTE: Using if-statement instead of `[ -L "$dst" ] && rm "$dst"` because
# under set -e, a compound `cmd1 && cmd2` at top level exits on false from cmd1.
for skill in capture recall memory build; do
  dst="$CLAUDE_HOME/skills/curator-$skill.md"
  if [ -L "$dst" ]; then
    rm "$dst"
    curator_log INFO "removed symlink: $dst"
  fi
done

# --- 3. Handle state dir ---
if [ "$MODE" = "purge" ]; then
  rm -rf "$CURATOR_STATE"
  curator_log INFO "purged state dir: $CURATOR_STATE"
else
  curator_log INFO "state dir preserved: $CURATOR_STATE"
fi

curator_log INFO "Uninstall complete."
