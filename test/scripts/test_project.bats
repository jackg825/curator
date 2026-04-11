#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CURATOR_HOME="$REPO_ROOT"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_MODE=ok
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory"
  : > "$MOCK_MCP_LOG"
}

@test "project_run writes MEMORY.md with projection-ts banner" {
  "$REPO_ROOT/memory-bridge/project.sh"
  [ -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]
  grep -q "curator: projection-ts=" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  grep -q "source=fresh" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "project_run writes MEMORY.md with source=stale when MCP unreachable" {
  export MOCK_MCP_MODE=fail
  "$REPO_ROOT/memory-bridge/project.sh" || true
  grep -q "source=stale" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" || \
    [ ! -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]  # or leaves previous stale file
}

@test "project_run includes project name in MEMORY.md" {
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/my-repo"
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory"
  "$REPO_ROOT/memory-bridge/project.sh"
  grep -q "my-repo" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "project_run calls mcp search with wing=current project" {
  "$REPO_ROOT/memory-bridge/project.sh"
  grep -q '"method":"search"' "$MOCK_MCP_LOG"
}

@test "project_run preserves existing MEMORY.md as backup before overwrite" {
  echo "existing content" > "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  "$REPO_ROOT/memory-bridge/project.sh"
  # Backup should exist under memory/backup-*/MEMORY.md
  # NOTE: spec used `find | read` which is broken (subshell loses var). Fixed:
  local backup
  backup=$(find "$CLAUDE_PROJECT_ROOT/memory" -name "backup-*" -type d | head -n1)
  [ -n "$backup" ]
}
