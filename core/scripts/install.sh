#!/usr/bin/env bash
# core/scripts/install.sh — deploy curator into ~/.claude and ~/.curator.
# Safe to re-run (idempotent). Reverse with uninstall.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURATOR_HOME="${CURATOR_HOME:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
source "$SCRIPT_DIR/../lib/common.sh"

: "${CLAUDE_HOME:=$HOME/.claude}"
: "${CURATOR_STATE:=$HOME/.curator}"

SKIP_PREFLIGHT=0
SKIP_MCP=0
for arg in "$@"; do
  case "$arg" in
    --skip-preflight) SKIP_PREFLIGHT=1 ;;
    --skip-mcp) SKIP_MCP=1 ;;
    --help|-h)
      echo "Usage: install.sh [--skip-preflight] [--skip-mcp]"
      exit 0
      ;;
  esac
done

# --- 1. Preflight ---
if [ "$SKIP_PREFLIGHT" = "0" ]; then
  curator_log INFO "Running preflight check..."
  "$SCRIPT_DIR/preflight-check.sh"
fi

# --- 2. Ensure state dir + device-id ---
mkdir -p "$CURATOR_STATE"
curator_device_id > /dev/null || true  # ensures file exists; || true absorbs SIGPIPE (tr|head) on macOS bash 3.2
device_id="$(cat "$CURATOR_STATE/device-id")"
curator_log INFO "device-id: $device_id"

# --- 3. Backup existing memdir ---
curator_log INFO "Backing up existing memdir content..."
backup_count=0
if [ -d "$CLAUDE_HOME/projects" ]; then
  while IFS= read -r mem; do
    repo_memory="$(dirname "$mem")"
    ts="$(date -u +%Y%m%d-%H%M%S)"
    backup_dir="$repo_memory/backup-$ts"
    mkdir -p "$backup_dir"
    cp -r "$repo_memory"/*.md "$backup_dir/" 2>/dev/null || true
    backup_count=$((backup_count + 1))
    curator_log INFO "  backed up: $repo_memory → $backup_dir"
  done < <(find "$CLAUDE_HOME/projects" -maxdepth 4 -name "MEMORY.md" -size +0 2>/dev/null)
fi
curator_log INFO "memdir backups: $backup_count"

# --- 4. Symlink skills into ~/.claude/skills/ ---
mkdir -p "$CLAUDE_HOME/skills"
for skill in capture recall memory build; do
  src="$CURATOR_HOME/skills/$skill.md"
  dst="$CLAUDE_HOME/skills/curator-$skill.md"
  if [ -f "$src" ]; then
    ln -sf "$src" "$dst"
    curator_log INFO "  linked skill: $dst → $src"
  fi
done

# --- 5. Patch settings.json ---
settings="$CLAUDE_HOME/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"

# Build curator hook config
curator_config=$(jq -cn \
  --arg session_start "$CURATOR_HOME/core/hooks/session-start.sh" \
  --arg user_prompt "$CURATOR_HOME/core/hooks/user-prompt-submit.sh" \
  --arg stop_hook "$CURATOR_HOME/core/hooks/stop.sh" \
  '{
    session_start: [{ matcher: "", hooks: [{ type: "command", command: $session_start, timeout: 15 }] }],
    user_prompt_submit: [{ matcher: "", hooks: [{ type: "command", command: $user_prompt, timeout: 600 }] }],
    stop: [{ matcher: "", hooks: [{ type: "command", command: $stop_hook, timeout: 600 }] }]
  }')

# Apply the patch using the jq filter (idempotent by command string dedup)
tmp_settings=$(mktemp)
jq -f "$CURATOR_HOME/core/templates/settings.json.patch.jq" \
   --argjson curator "$curator_config" "$settings" > "$tmp_settings"
mv "$tmp_settings" "$settings"
curator_log INFO "patched $settings"

# --- 6. Check optional MemPalace CLI dependency ---
if [ "$SKIP_MCP" = "0" ]; then
  source "$CURATOR_HOME/core/lib/mempalace-cli.sh"
  if mempalace_available; then
    curator_log INFO "mempalace CLI detected — /curator:recall will use semantic search"
  else
    curator_log INFO "mempalace CLI not installed — /curator:recall will fall back to local grep (install hint: see https://github.com/milla-jovovich/mempalace)"
  fi
fi

# --- 7. Write install receipt ---
receipt="$CURATOR_STATE/install-receipt.json"
hook_snapshot=$(jq -c '.hooks' "$settings")
jq -cn \
  --arg version "1.2.0" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg device "$device_id" \
  --argjson hooks "$hook_snapshot" \
  '{
    version: $version,
    installed_at: $ts,
    device_id: $device,
    hook_order_snapshot: $hooks,
    curator_home: env.CURATOR_HOME
  }' > "$receipt"
curator_log INFO "install receipt: $receipt"

curator_log INFO "Install complete."
