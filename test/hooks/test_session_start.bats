#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CLAUDE_SESSION_ID="test-sess-1"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  export MOCK_MCP_MODE=ok
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory" "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"
  echo "mac-test" > "$CURATOR_STATE/device-id"
}

@test "session-start resets session-state.json proposal_count to 0" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  local count
  count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
  [ "$count" = "0" ]
}

@test "session-start records session_id in session-state.json" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  local sid
  sid=$(jq -r .session_id "$CURATOR_STATE/session-state.json")
  [ "$sid" = "test-sess-1" ]
}

@test "session-start creates MEMORY.md via project.sh" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  [ -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]
}

@test "session-start invokes reconcile when pending_sync has entries" {
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/journal.sh"
  journal_append "feedback" '{"text":"pre-existing pending"}'
  "$REPO_ROOT/core/hooks/session-start.sh"
  local pending
  pending=$(jq -s 'map(select(.pending | length > 0)) | length' \
    "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending" = "0" ]
}

@test "session-start exits 0 even when MemPalace unreachable" {
  export MOCK_MCP_MODE=fail
  run "$REPO_ROOT/core/hooks/session-start.sh"
  [ "$status" -eq 0 ]
  # MEMORY.md still written with stale banner
  grep -q "source=stale" "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
}

@test "session-start is fast enough (under 15 seconds)" {
  local start
  start=$(date +%s)
  "$REPO_ROOT/core/hooks/session-start.sh"
  local end
  end=$(date +%s)
  [ "$((end - start))" -lt 15 ]
}
