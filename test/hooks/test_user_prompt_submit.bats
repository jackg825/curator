#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export CURATOR_HOME="$REPO_ROOT"
  export CURATOR_STATE="$BATS_TEST_TMPDIR/.curator"
  export CLAUDE_SESSION_ID="sess-test"
  mkdir -p "$CURATOR_STATE/pattern-candidates"
  jq -cn --arg sid "$CLAUDE_SESSION_ID" \
    '{session_id:$sid, proposal_count:0, last_proposal_ts:null}' \
    > "$CURATOR_STATE/session-state.json"
}

@test "hook exits 0 with no stderr when no candidates exist" {
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hook emits proposal via exit 2 when candidate exists and count is 0" {
  echo "prefer pnpm over npm in this repo" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pattern"* ]]
  [[ "$output" == *"pnpm"* ]]
  [[ "$output" == *"Y/n/d"* ]]
}

@test "hook increments proposal_count after emitting" {
  echo "some rule" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  "$REPO_ROOT/core/hooks/user-prompt-submit.sh" || true
  local count
  count=$(jq -r .proposal_count "$CURATOR_STATE/session-state.json")
  [ "$count" = "1" ]
}

@test "hook does NOT emit when proposal_count already >= 1 (HR-2 cap)" {
  echo "second rule" > "$CURATOR_STATE/pattern-candidates/sess-test.txt"
  jq -cn '{session_id:"sess-test", proposal_count:1}' > "$CURATOR_STATE/session-state.json"
  run "$REPO_ROOT/core/hooks/user-prompt-submit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"pattern"* ]] || [ -z "$output" ]
}

@test "hook removes candidate after emitting (consumed)" {
  local cfile="$CURATOR_STATE/pattern-candidates/sess-test.txt"
  echo "one shot" > "$cfile"
  "$REPO_ROOT/core/hooks/user-prompt-submit.sh" || true
  [ ! -s "$cfile" ]
}
