#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/core/lib/common.sh"
  source "$REPO_ROOT/memory-bridge/router.sh"
  export CURATOR_RULES="$REPO_ROOT/memory-bridge/routing-rules.yaml"
}

@test "router_match returns 'memory:immediate,mempalace:batch' for feedback >= 50 chars" {
  local text="this is a feedback message that is definitely longer than fifty characters for the test"
  run router_match "feedback" "$text"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:immediate"* ]]
  [[ "$output" == *"mempalace:batch"* ]]
}

@test "router_match returns 'memory:skip,mempalace:batch' for session_observation" {
  run router_match "session_observation" "short"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:skip"* ]]
  [[ "$output" == *"mempalace:batch"* ]]
}

@test "router_match returns 'memory:pattern_signal' for high-confidence pattern" {
  run router_match "pattern" "some text" "confidence=0.9"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory:pattern_signal"* ]]
}

@test "router_match falls through with memory:skip,mempalace:skip for unknown type" {
  run router_match "unknown_type" "x"
  # Either exits 0 with skip:skip or returns non-zero with clear message
  [[ "$output" == *"skip"* ]] || [ "$status" -ne 0 ]
}

@test "router_match skips short feedback (below min_length)" {
  run router_match "feedback" "short"
  # Rule requires min_length 50, so this should not match the feedback rule
  [[ "$output" != *"mempalace:batch"* ]] || [[ "$output" == *"skip"* ]]
}
