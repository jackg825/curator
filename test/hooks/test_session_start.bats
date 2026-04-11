#!/usr/bin/env bats
# v1.2: SessionStart only resets per-session state. L0 projection deleted.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  export CLAUDE_SESSION_ID="test-sess-1"
  mkdir -p "$CLAUDE_PROJECT_ROOT/memory" "$CURATOR_STATE"
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

@test "session-start records started_at timestamp" {
  "$REPO_ROOT/core/hooks/session-start.sh"
  local ts
  ts=$(jq -r .started_at "$CURATOR_STATE/session-state.json")
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "session-start exits 0 unconditionally" {
  run "$REPO_ROOT/core/hooks/session-start.sh"
  [ "$status" -eq 0 ]
}

@test "session-start does NOT touch MEMORY.md (v1.2: no projection)" {
  rm -f "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md"
  "$REPO_ROOT/core/hooks/session-start.sh"
  [ ! -e "$CLAUDE_PROJECT_ROOT/memory/MEMORY.md" ]
}

@test "session-start is fast enough (under 15 seconds)" {
  local start
  start=$(date +%s)
  "$REPO_ROOT/core/hooks/session-start.sh"
  local end
  end=$(date +%s)
  [ "$((end - start))" -lt 15 ]
}
