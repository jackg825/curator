#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CLAUDE_HOME="$BATS_TEST_TMPDIR/.claude"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CURATOR_HOME="$REPO_ROOT"  # run from source tree
  export CURATOR_SKIP_MCP=1         # skip MCP verification in install
  mkdir -p "$CLAUDE_HOME"
  cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "existing-stop-hook.sh" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "secret-scan.sh" } ] }
    ]
  }
}
EOF
  # Create a populated memdir so backup path is exercised
  mkdir -p "$CLAUDE_HOME/projects/-Users-test-repoX/memory"
  echo "old content" > "$CLAUDE_HOME/projects/-Users-test-repoX/memory/MEMORY.md"
}

@test "install writes install-receipt.json" {
  run "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  [ "$status" -eq 0 ]
  [ -f "$CURATOR_STATE/install-receipt.json" ]
  jq -e '.version, .installed_at, .device_id, .hook_order_snapshot' \
    "$CURATOR_STATE/install-receipt.json" > /dev/null
}

@test "install appends curator hooks to Stop without removing existing" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local stop_count
  stop_count=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  [ "$stop_count" -ge 2 ]  # existing + curator
  # Existing hook must still be present
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(. == "existing-stop-hook.sh")' \
    "$CLAUDE_HOME/settings.json" > /dev/null
  # Curator hook must be present
  jq -e '.hooks.Stop | map(.hooks[0].command) | any(contains("curator") or contains("stop.sh"))' \
    "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install creates SessionStart and UserPromptSubmit hooks when slots empty" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  jq -e '.hooks.SessionStart | length >= 1' "$CLAUDE_HOME/settings.json" > /dev/null
  jq -e '.hooks.UserPromptSubmit | length >= 1' "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install preserves PreToolUse hooks untouched" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  jq -e '.hooks.PreToolUse | length == 1' "$CLAUDE_HOME/settings.json" > /dev/null
  jq -e '.hooks.PreToolUse[0].hooks[0].command == "secret-scan.sh"' \
    "$CLAUDE_HOME/settings.json" > /dev/null
}

@test "install backs up existing memdir content" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  # Backup dir should exist and contain the old content.
  # NOTE: spec used `find | read` which is broken (subshell loses var). Fixed:
  local backup_dir
  backup_dir=$(find "$CLAUDE_HOME/projects/-Users-test-repoX/memory" -type d -name "backup-*" | head -n1)
  [ -n "$backup_dir" ]
  grep -q "old content" "$backup_dir/MEMORY.md"
}

@test "install generates device-id on first run and keeps it stable" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local id1
  id1=$(cat "$CURATOR_STATE/device-id")
  [ -n "$id1" ]
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local id2
  id2=$(cat "$CURATOR_STATE/device-id")
  [ "$id1" = "$id2" ]
}

@test "install is idempotent (no duplicate hooks on second run)" {
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local count1
  count1=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  "$REPO_ROOT/core/scripts/install.sh" --skip-preflight --skip-mcp
  local count2
  count2=$(jq '.hooks.Stop | length' "$CLAUDE_HOME/settings.json")
  [ "$count1" = "$count2" ]
}
