#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export MOCK_MCP_LOG="$BATS_TEST_TMPDIR/mock-mcp.log"
  mkdir -p "$CURATOR_STATE"
  : > "$MOCK_MCP_LOG"

  # Route calls through the mock
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"

  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/mcp-client.sh"
}

@test "mcp_ping returns 0 when mock responds OK" {
  export MOCK_MCP_MODE=ok
  run mcp_ping
  [ "$status" -eq 0 ]
}

@test "mcp_ping returns non-zero when mock fails" {
  export MOCK_MCP_MODE=fail
  run mcp_ping
  [ "$status" -ne 0 ]
}

@test "mcp_search returns JSON array" {
  export MOCK_MCP_MODE=ok
  run mcp_search "auth refresh"
  [ "$status" -eq 0 ]
  # Output should be parseable JSON with array under .result
  echo "$output" | jq -e '.result | type == "array"' > /dev/null
}

@test "mcp_write sends type and payload to server" {
  export MOCK_MCP_MODE=ok
  mcp_write "feedback" '{"text":"test"}'
  grep -q '"method":"write"' "$MOCK_MCP_LOG"
  grep -q '"text":"test"' "$MOCK_MCP_LOG"
}

@test "mcp_write returns non-zero when server fails" {
  export MOCK_MCP_MODE=fail
  run mcp_write "feedback" '{"text":"x"}'
  [ "$status" -ne 0 ]
}
