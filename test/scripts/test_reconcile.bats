#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mcp.log"
  mkdir -p "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/journal.sh"
  echo "test-device" > "$CURATOR_STATE/device-id"
}

@test "reconcile marks pending entries as resolved after successful retry" {
  export MOCK_MCP_MODE=ok
  journal_append "feedback" '{"text":"needs retry"}'
  "$REPO_ROOT/memory-bridge/reconcile.sh"
  # Pending array should now be empty
  local pending_count
  pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending_count" -eq 0 ]
}

@test "reconcile leaves entries pending when MCP fails" {
  export MOCK_MCP_MODE=fail
  journal_append "feedback" '{"text":"fail case"}'
  "$REPO_ROOT/memory-bridge/reconcile.sh" || true
  local pending_count
  pending_count=$(jq -s 'map(select(.pending | length > 0)) | length' "$CURATOR_STATE/pending_sync.jsonl")
  [ "$pending_count" -ge 1 ]
}

@test "reconcile is a no-op when no pending entries" {
  # Empty journal file
  : > "$CURATOR_STATE/pending_sync.jsonl"
  run "$REPO_ROOT/memory-bridge/reconcile.sh"
  [ "$status" -eq 0 ]
}

@test "reconcile prunes entries older than 7 days" {
  cat > "$CURATOR_STATE/pending_sync.jsonl" <<'OLD'
{"content_hash":"old","ts":"2020-01-01T00:00:00Z","device_id":"x","type":"feedback","payload":{"text":"ancient"},"pending":["mempalace"]}
OLD
  export MOCK_MCP_MODE=ok
  "$REPO_ROOT/memory-bridge/reconcile.sh"
  # Old entry should be removed
  run grep -c "old" "$CURATOR_STATE/pending_sync.jsonl"
  [ "$output" = "0" ] || [ "$status" -ne 0 ]
}
