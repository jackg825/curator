#!/usr/bin/env bats
# Regression tests for the v1.1 stub: stdio MCP transport must fail loudly
# (issue #1). These tests guard against any future regression that silently
# enables stdio dispatch without a real implementation.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  mkdir -p "$CURATOR_STATE"
  # Force the default stdio transport for every test in this file
  unset CURATOR_MEMPALACE_URL
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/core/lib/mcp-client.sh"
}

@test "mcp_ping returns non-zero with default stdio transport" {
  run mcp_ping
  [ "$status" -ne 0 ]
}

@test "mcp_search returns non-zero with default stdio transport" {
  run mcp_search "any query"
  [ "$status" -ne 0 ]
}

@test "mcp_write returns non-zero with default stdio transport" {
  run mcp_write "feedback" '{"text":"x"}'
  [ "$status" -ne 0 ]
}

@test "stdio dispatch logs error pointing at issue #1" {
  # mcp_ping suppresses stderr, so use mcp_search to surface the dispatch error
  run mcp_search "anything"
  [ "$status" -ne 0 ]
  [[ "$output" == *"issue"* ]] || [[ "$output" == *"not implemented"* ]]
}

@test "health-check.sh reports mcp_transport: unimplemented when stdio default" {
  unset CURATOR_MEMPALACE_URL
  run "$REPO_ROOT/core/scripts/health-check.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mcp_transport == "unimplemented"' > /dev/null
}

@test "health-check.sh reports mcp_transport: mock when mock URL configured" {
  export CURATOR_MEMPALACE_URL="mock://$REPO_ROOT/test/fixtures/mock-mempalace.sh"
  run "$REPO_ROOT/core/scripts/health-check.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mcp_transport == "mock"' > /dev/null
}
